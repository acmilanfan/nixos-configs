package telegram

import "testing"

// Telegram rejects messages.getDialogs when offset_peer is missing
// (gotd cannot encode a nil union field — real-world error:
// "field offset_peer is nil"). The initial request must carry
// InputPeerEmpty.
func TestDialogsRequestFillsRequiredOffsetPeer(t *testing.T) {
	req := dialogsRequest(200)
	if req == nil {
		t.Fatal("dialogsRequest() = nil")
	}
	if req.OffsetPeer == nil {
		t.Fatal("OffsetPeer is nil; Telegram will refuse to encode the request")
	}
	if req.Limit != 200 {
		t.Fatalf("Limit = %d, want 200", req.Limit)
	}
}
