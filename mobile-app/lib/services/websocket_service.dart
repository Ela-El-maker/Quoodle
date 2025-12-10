import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/environment.dart';

class WebsocketService {
  WebsocketService({WebSocketChannel? channel}) : _channel = channel;

  final WebSocketChannel? _channel;

  WebSocketChannel connect() {
    return _channel ?? WebSocketChannel.connect(Uri.parse(Environment.wsBaseUrl));
  }
}
