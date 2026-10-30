/**
 * Inspects user-uploaded PDFs in Storage and quarantines any that are not
 * valid PDFs or that contain active content. Covers ticket attachments
 * (attachments/) and chat attachments (chat/).
 *
 * This is a structural check, not an antivirus scan. It rejects files that
 * aren't PDFs and PDFs that use features able to run code or open programs
 * or files when opened (JavaScript, launch actions, embedded files). A
 * PDF's object streams can be compressed, so a determined attacker could
 * hide these markers. A real malware scanner is still needed for full
 * coverage.
 *
 * Quarantined files are moved to quarantine/, which no client rule allows
 * anyone to read, so the link stored in the ticket or chat stops working.
 */
const {onObjectFinalized} = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");

const MAX_PDF_BYTES = 15 * 1024 * 1024;
const WATCHED_PREFIXES = ["attachments/", "chat/"];

// Markers that let a PDF run script or start a program when opened.
const ACTIVE_CONTENT_MARKERS = [
  /\/JavaScript\b/,
  /\/JS\b/,
  /\/Launch\b/,
  /\/EmbeddedFile\b/,
  /\/RichMedia\b/,
  /\/ImportData\b/,
  /\/SubmitForm\b/,
];

/**
 * Returns a reason the buffer should be quarantined, or null if it looks
 * like a safe PDF.
 * @param {Buffer} buffer The full file contents.
 * @return {string|null}
 */
function inspectPdf(buffer) {
  if (buffer.length > MAX_PDF_BYTES) return "file is larger than 15 MB";
  if (buffer.subarray(0, 5).toString("latin1") !== "%PDF-") {
    return "file does not start with a PDF signature";
  }
  const text = buffer.toString("latin1");
  const marker = ACTIVE_CONTENT_MARKERS.find((re) => re.test(text));
  return marker ? `contains active content (${marker.source})` : null;
}

exports.inspectPdf = inspectPdf;

exports.scanUploadedPdf = onObjectFinalized(async (event) => {
  const {name, contentType, bucket: bucketName, size} = event.data;
  if (!name || !WATCHED_PREFIXES.some((prefix) => name.startsWith(prefix))) {
    return;
  }
  const claimsPdf =
    contentType === "application/pdf" || name.toLowerCase().endsWith(".pdf");
  if (!claimsPdf) return;

  const file = admin.storage().bucket(bucketName).file(name);
  if (Number(size) > MAX_PDF_BYTES) {
    await file.move(`quarantine/${name}`);
    console.warn(`Quarantined ${name}: file is larger than 15 MB`);
    return;
  }

  const [buffer] = await file.download();
  const problem = inspectPdf(buffer);
  if (!problem) return;

  await file.move(`quarantine/${name}`);
  console.warn(`Quarantined ${name}: ${problem}`);
});
