// Lượng khách mỗi ngày: thời tiết thật ở Đà Nẵng (Open-Meteo, miễn phí, không cần khoá),
// ngày thật trên lịch (cuối tuần, ngày lương, ngày lễ), sự kiện trong phố và quảng cáo.
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Một yếu tố ảnh hưởng tới lượng khách
class CrowdFactor {
  final String emoji, label;
  final double delta; // +0.2 = đông hơn 20%
  const CrowdFactor(this.emoji, this.label, this.delta);
  String get pct => '${delta >= 0 ? '+' : '−'}${(delta.abs() * 100).round()}%';
}

/// Thời tiết hiện tại
class WeatherNow {
  final double temp;
  final int code;
  final DateTime at;
  WeatherNow(this.temp, this.code, this.at);
  bool get rain => (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
  bool get storm => code >= 95;
  String get emoji => storm ? '⛈️' : (rain ? '🌧️' : (code >= 45 && code <= 48 ? '🌫️' : (code == 0 ? '☀️' : '⛅')));
  String get text => storm ? 'Giông bão' : (rain ? 'Mưa' : (code >= 45 && code <= 48 ? 'Sương mù' : (code == 0 ? 'Trời nắng' : 'Có mây')));
}

/// Quảng cáo: (id, emoji, tên, giá, tăng khách, số ngày)
const adTypes = [
  ('flyer', '📄', 'Phát tờ rơi', 80, 0.15, 2),
  ('radio', '📻', 'Quảng cáo báo, đài', 220, 0.30, 3),
  ('tv', '📺', 'Quảng cáo tivi', 600, 0.50, 4),
];

class Crowd {
  static WeatherNow? weather;
  static String weatherErr = '';
  static bool _loading = false;

  /// Lấy thời tiết thật ở Hoà Xuân, Cẩm Lệ, Đà Nẵng (làm mới mỗi 30 phút)
  static Future<void> fetchWeather() async {
    final w = weather;
    if (_loading || (w != null && DateTime.now().difference(w.at).inMinutes < 30)) return;
    _loading = true;
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=16.02&longitude=108.21&current=temperature_2m,weather_code&timezone=Asia%2FBangkok');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final cur = (jsonDecode(res.body) as Map<String, dynamic>)['current'] as Map<String, dynamic>;
        weather = WeatherNow((cur['temperature_2m'] as num).toDouble(), (cur['weather_code'] as num).toInt(), DateTime.now());
        weatherErr = '';
      } else {
        weatherErr = 'Không lấy được thời tiết';
      }
    } catch (_) {
      weatherErr = 'Không lấy được thời tiết (mất mạng?)';
    } finally {
      _loading = false;
    }
  }

  static double _h(String s) {
    var h = 7;
    for (final u in s.codeUnits) {
      h = (h * 31 + u) % 1000003;
    }
    return (h % 10007) / 10007;
  }

  /// Ngày lễ thật (dương lịch + vài ngày âm lịch đã đổi sẵn)
  static String? holiday(DateTime d) {
    final k = d.month * 100 + d.day;
    const fixed = {
      101: '🎆 Tết Dương lịch',
      214: '💘 Lễ Tình nhân',
      308: '🌷 Quốc tế Phụ nữ 8/3',
      430: '🇻🇳 Ngày Giải phóng 30/4',
      501: '🛠️ Quốc tế Lao động 1/5',
      601: '🧸 Quốc tế Thiếu nhi 1/6',
      902: '🇻🇳 Quốc khánh 2/9',
      1020: '💐 Phụ nữ Việt Nam 20/10',
      1120: '📚 Nhà giáo Việt Nam 20/11',
      1224: '🎄 Đêm Giáng sinh',
      1225: '🎄 Giáng sinh',
      1231: '🎇 Giao thừa dương lịch',
    };
    final f = fixed[k];
    if (f != null) return f;
    // Tết Nguyên đán & Trung thu (âm lịch) của các năm tới
    const lunar = {
      20270205: '🧧 Tất niên', 20270206: '🧧 Mùng 1 Tết', 20270207: '🧧 Mùng 2 Tết', 20270208: '🧧 Mùng 3 Tết',
      20270915: '🥮 Tết Trung thu',
      20280125: '🧧 Tất niên', 20280126: '🧧 Mùng 1 Tết', 20280127: '🧧 Mùng 2 Tết', 20280128: '🧧 Mùng 3 Tết',
      20281003: '🥮 Tết Trung thu',
    };
    return lunar[d.year * 10000 + d.month * 100 + d.day];
  }

  /// Sự kiện trong phố hôm nay (trong game, giống nhau trên 2 máy vì dựa theo ngày)
  static CrowdFactor? streetEvent(DateTime d, String venueId) {
    final key = '${d.year}-${d.month}-${d.day}';
    if (_h('ev$key') > 0.45) return null; // khoảng 45% số ngày có sự kiện
    final grill = venueId == 'goyuhan' || venueId == 'binhdan';
    final sea = venueId == 'poseidon';
    final list = <CrowdFactor>[
      const CrowdFactor('🎵', 'Ca nhạc đường phố trên đường Hoà Xuân', 0.15),
      CrowdFactor('⚽', 'Tối nay có trận bóng lớn, dân nhậu kéo đi xem', grill ? 0.25 : 0.05),
      const CrowdFactor('🚧', 'Đường Nguyễn Phước Lan đang sửa, khó đi lại', -0.15),
      const CrowdFactor('🎪', 'Khu phố mở hội chợ ẩm thực', 0.20),
      CrowdFactor('🦀', 'Tàu cá về bến, hải sản tươi rẻ', sea ? 0.25 : 0.0),
      const CrowdFactor('🤧', 'Đang mùa cúm, mọi người ngại ra ngoài', -0.10),
      const CrowdFactor('🌊', 'Triều cường ven sông Hói Kiểng', -0.10),
      const CrowdFactor('🎓', 'Sinh viên vừa thi xong, rủ nhau đi ăn', 0.15),
      const CrowdFactor('🏃', 'Giải chạy bộ ven sông, sáng nay đông người', 0.10),
    ];
    return list[(_h('pick$key') * list.length).floor() % list.length];
  }

  /// Các yếu tố của hôm nay
  static List<CrowdFactor> factors({required String venueId, required bool sig, required int sigRank, required Map<String, int> ads, required int day}) {
    final now = DateTime.now();
    final out = <CrowdFactor>[];
    final grill = venueId == 'goyuhan' || venueId == 'binhdan';
    // thời tiết thật
    final w = weather;
    if (w != null) {
      final t = w.temp.round();
      if (w.rain || w.storm) {
        out.add(grill
            ? CrowdFactor(w.emoji, 'Đà Nẵng ${w.text.toLowerCase()} $t°C – thèm đồ nướng, đồ nhậu', 0.10)
            : CrowdFactor(w.emoji, 'Đà Nẵng ${w.text.toLowerCase()} $t°C – ngại ra đường', w.storm ? -0.25 : -0.15));
      } else if (w.temp >= 34) {
        out.add(CrowdFactor('🥵', 'Đà Nẵng nắng nóng $t°C', venueId == 'cafe' || venueId == 'poseidon' ? 0.05 : -0.10));
      } else if (w.temp < 22) {
        out.add(CrowdFactor('🧥', 'Đà Nẵng trời se lạnh $t°C', venueId == 'goyuhan' ? 0.15 : 0.0));
      } else {
        out.add(CrowdFactor(w.emoji, 'Đà Nẵng ${w.text.toLowerCase()} $t°C – thời tiết đẹp', 0.10));
      }
    }
    // lịch thật
    final wd = now.weekday;
    if (wd == DateTime.saturday || wd == DateTime.sunday) {
      out.add(CrowdFactor('📅', 'Cuối tuần', venueId == 'poseidon' ? 0.30 : 0.20));
    } else if (wd == DateTime.friday) {
      out.add(const CrowdFactor('📅', 'Tối thứ Sáu', 0.10));
    }
    if (now.day <= 5 || now.day >= 28) out.add(const CrowdFactor('💵', 'Đầu/cuối tháng, mọi người vừa có lương', 0.10));
    final hol = holiday(now);
    if (hol != null) out.add(CrowdFactor(hol.split(' ').first, '${hol.substring(hol.indexOf(' ') + 1)} – ngày lễ', 0.30));
    // sự kiện trong phố
    final ev = streetEvent(now, venueId);
    if (ev != null && ev.delta != 0) out.add(ev);
    // hạng nhà hàng riêng
    if (sig && sigRank > 1) out.add(CrowdFactor('⭐', 'Quán hạng $sigRank sao nổi tiếng', 0.06 * (sigRank - 1)));
    // quảng cáo đang chạy
    for (final a in adTypes) {
      final until = ads[a.$1] ?? 0;
      if (day < until) out.add(CrowdFactor(a.$2, '${a.$3} (còn ${until - day} ngày)', a.$5));
    }
    return out;
  }

  static double total(List<CrowdFactor> f) {
    var m = 1.0;
    for (final x in f) {
      m *= 1 + x.delta;
    }
    return m.clamp(0.6, 2.3).toDouble();
  }

  static String fmt(double m) => '×${m.toStringAsFixed(2)}';
}
