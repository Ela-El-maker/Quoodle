from app.api_controller import build_dispatch_response


def test_dispatch_response_fields():
    resp = build_dispatch_response('dispatched', 'PC001', 'CMD-1')
    assert resp['status'] == 'dispatched'

