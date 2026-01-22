#pragma once

int quoodle_sign_ed25519(const char *priv_b64, const char *msg, char **sig_b64);
int quoodle_verify_ed25519(const char *pub_b64, const char *msg, const char *sig_b64);
