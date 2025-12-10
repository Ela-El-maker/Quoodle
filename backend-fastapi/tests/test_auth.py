from app.ws.protocol import iso_timestamp


def test_iso_timestamp_format():
    value = iso_timestamp()
    assert value.endswith('Z')
