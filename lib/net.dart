import 'package:supabase_flutter/supabase_flutter.dart';

/// Bọc Supabase Realtime Broadcast: mọi thông điệp dùng chung event 'm'.
class Net {
  RealtimeChannel? _ch;
  bool ready = false;

  Future<void> connect(
    String code,
    void Function(Map<String, dynamic>) onMsg,
    void Function() onReady,
    void Function(String) onError,
  ) async {
    await disconnect();
    final ch = Supabase.instance.client.channel('nhahang-$code', opts: const RealtimeChannelConfig(self: false));
    ch.onBroadcast(
      event: 'm',
      callback: (p) {
        // Tuỳ phiên bản, callback nhận payload gốc hoặc cả gói {type,event,payload}
        final d = p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : Map<String, dynamic>.from(p);
        onMsg(d);
      },
    );
    ch.subscribe((status, err) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        ready = true;
        onReady();
      } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        ready = false;
        onError(err?.toString() ?? status.name);
      }
    });
    _ch = ch;
  }

  void send(Map<String, dynamic> m) {
    if (!ready) return;
    _ch?.sendBroadcastMessage(event: 'm', payload: m);
  }

  Future<void> disconnect() async {
    final c = _ch;
    _ch = null;
    ready = false;
    if (c != null) {
      await Supabase.instance.client.removeChannel(c);
    }
  }
}
