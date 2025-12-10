from app.ws.protocol import build_auth_ack

def test_update_flow_ack_has_policy_hash():
    ack = build_auth_ack('PC001', 'sess-123')
    assert 'policy_hash' in ack['body']
