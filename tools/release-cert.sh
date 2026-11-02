#!/bin/zsh
# The self-signed certificate that signs Showreel releases until there is a
# Developer ID. macOS ties Screen Recording, Microphone, and Camera permission
# to the app's signature. An ad-hoc signature changes with every build, so
# every update lost its permissions. A certificate that never changes keeps
# them: each release passes the same "certificate root = H..." requirement.
#
# The certificate is not trusted by Gatekeeper, so the first open still needs
# Open Anyway. That stays the same until releases are notarized.
#
# Usage: tools/release-cert.sh           make the certificate once (kept in
#                                        ~/Library/Developer/Showreel/release-signing)
#        tools/release-cert.sh --trust   also add it to the login keychain and trust
#                                        it for code signing, so ./build.sh signs
#                                        local builds the same way (asks for your password)
#        tools/release-cert.sh --upload  also store it in the GitHub secrets
#                                        SELF_SIGNED_CERTIFICATE(_PASSWORD) for release.yml
#
# Back up the folder. Losing the key means the next release has a new
# signature, and everyone has to allow Screen Recording once more.
set -euo pipefail
name="Showreel Release Signing"
dir="$HOME/Library/Developer/Showreel/release-signing"
p12="$dir/cert.p12"
pem="$dir/cert.pem"
pass_file="$dir/password"

if [[ ! -f "$p12" ]]; then
  mkdir -p "$dir" && chmod 700 "$dir"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  # 30 years: the signature is checked against the certificate's dates.
  openssl req -x509 -newkey rsa:3072 -nodes -days 10950 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$pem" 2>/dev/null
  uuidgen > "$pass_file" && chmod 600 "$pass_file"
  # -legacy: the Keychain's importer reads only the older PKCS#12 ciphers.
  openssl pkcs12 -export -legacy -name "$name" -inkey "$tmp/key.pem" -in "$pem" \
    -out "$p12" -passout "file:$pass_file"
  chmod 600 "$p12"
  echo "made $p12"
fi
sha1=$(openssl x509 -in "$pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
echo "certificate: $name ($sha1)"

if [[ " $* " == *" --trust "* ]]; then
  login="$HOME/Library/Keychains/login.keychain-db"
  if ! security find-identity -p codesigning "$login" | grep -q "$sha1"; then
    security import "$p12" -k "$login" -P "$(<"$pass_file")" -T /usr/bin/codesign
  fi
  security add-trusted-cert -r trustRoot -p codeSign -k "$login" "$pem"
  security find-identity -v -p codesigning | grep -q "$sha1" && echo "trusted for code signing"
fi

if [[ " $* " == *" --upload "* ]]; then
  base64 -i "$p12" | gh secret set SELF_SIGNED_CERTIFICATE
  gh secret set SELF_SIGNED_CERTIFICATE_PASSWORD < "$pass_file"
  echo "stored in the GitHub secrets SELF_SIGNED_CERTIFICATE and SELF_SIGNED_CERTIFICATE_PASSWORD"
fi
