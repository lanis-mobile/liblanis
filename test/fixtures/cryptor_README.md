# Cryptor fixtures

`cryptor_legacy_vectors.json` was generated using published liblanis 0.2.1 and
`encrypt` 5.0.3 before removing that dependency. Its deterministic test passphrase
contains bytes 0 through 45; the captured ciphertexts retain their random salts.
Messages cover AES block boundaries, Unicode, JSON and multiple blocks.

`cryptor_rsa.json` contains a generated 2048-bit RSA **test-only** private key and
its SPKI and PKCS1 public-key PEM encodings. It has never been used for accounts.

During this migration OpenSSL independently decrypted all seven legacy AES
vectors, eight newly encrypted messages (including empty plaintext), and a newly
encrypted RSA handshake. The committed tests retain legacy decryption coverage,
RSA format/padding checks, malformed input checks and round trips without adding
an OpenSSL dependency to the test suite.
