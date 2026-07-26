{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "otp-migration";
  buildInputs = with pkgs; [
    otpauth
    zbar
  ];
  shellHook = ''
    echo "=== OTP Migration Shell ==="
    echo ""
    echo "Step 1 — Scan QR code (from screenshot or camera):"
    echo "  zbarimg qr-screenshot.png"
    echo "  # or pipe from clipboard:  pngpaste - | zbarimg -"
    echo ""
    echo "Step 2 — Decode GA migration URL to otpauth:// URIs:"
    echo "  otpauth -link \"otpauth-migration://offline?data=...\""
    echo ""
    echo "Step 3 — Insert each URI into pass:"
    echo "  pass otp insert email/gmail"
    echo "  # paste: otpauth://totp/Gmail?secret=XXXX&issuer=Google"
    echo ""
    echo "Or append to an existing password entry:"
    echo "  pass otp append email/gmail"
    echo ""
    echo "pass and pass-otp are already available system-wide."
    echo "==========================="
  '';
}
