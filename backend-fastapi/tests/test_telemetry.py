from app.ws.protocol import build_auth_ack


def test_auth_ack_shape():
    ack = build_auth_ack('PC001', 'sess-1')
    assert ack['type'] == 'AUTH_ACK'
