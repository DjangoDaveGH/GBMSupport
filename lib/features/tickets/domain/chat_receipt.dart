/// One participant's delivery/read state on a ticket's chat
/// (tickets/{id}/chatReceipts/{uid}). [lastDeliveredAt] is written by the
/// onTicketActivityCreated Cloud Function the moment it's processed a new
/// comment for this participant (the best available proxy for "reached
/// their device" without a client-side delivery ack); [lastReadAt] is
/// written by the participant's own client when they actually view the
/// chat (TicketRepository.markChatRead).
class ChatReceipt {
  final DateTime? lastDeliveredAt;
  final DateTime? lastReadAt;

  const ChatReceipt({this.lastDeliveredAt, this.lastReadAt});
}
