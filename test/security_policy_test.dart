import 'package:flutter_test/flutter_test.dart';
import 'package:shiei_kiosk/config/app_config.dart';
import 'package:shiei_kiosk/features/exam_player/url_exam_player.dart';

void main() {
  group('AppConfig local HTTP & HTTPS policy', () {
    test('allows cleartext HTTP only for loopback and RFC1918 local IPs', () {
      expect(AppConfig.isLocalOrPrivateHost('localhost'), isTrue);
      expect(AppConfig.isLocalOrPrivateHost('127.0.0.1'), isTrue);
      expect(AppConfig.isLocalOrPrivateHost('192.168.1.100'), isTrue);
      expect(AppConfig.isLocalOrPrivateHost('10.20.30.40'), isTrue);
      expect(AppConfig.isLocalOrPrivateHost('172.16.5.4'), isTrue);
      expect(AppConfig.isLocalOrPrivateHost('server.local'), isTrue);

      expect(AppConfig.isLocalOrPrivateHost('172.32.0.1'), isFalse);
      expect(AppConfig.isLocalOrPrivateHost('8.8.8.8'), isFalse);
      expect(AppConfig.isLocalOrPrivateHost('exam.sekolah.sch.id'), isFalse);
    });

    test('normalizes bare local IP to http and bare public domain to https', () {
      expect(
        AppConfig.validateAndNormalizeServerUrl('192.168.1.50:8000'),
        equals('http://192.168.1.50:8000/api/v1'),
      );
      expect(
        AppConfig.validateAndNormalizeServerUrl('exam.sekolah.sch.id'),
        equals('https://exam.sekolah.sch.id/api/v1'),
      );
      expect(
        AppConfig.validateAndNormalizeServerUrl('https://exam.sekolah.sch.id/api/v1/'),
        equals('https://exam.sekolah.sch.id/api/v1'),
      );
    });

    test('rejects explicit cleartext HTTP on public domains', () {
      expect(AppConfig.validateAndNormalizeServerUrl('http://exam.sekolah.sch.id'), isNull);
      expect(AppConfig.validateAndNormalizeServerUrl('http://evil.com/api/v1'), isNull);
      expect(AppConfig.isAllowedServerBaseUrl('http://exam.sekolah.sch.id/api/v1'), isFalse);
      expect(AppConfig.isAllowedServerBaseUrl('http://192.168.10.20:8000/api/v1'), isTrue);
      expect(AppConfig.isAllowedServerBaseUrl('https://exam.sekolah.sch.id/api/v1'), isTrue);
    });
  });

  group('UrlExamPlayer WebView URL allowlist', () {
    const examUrl = 'https://cbt.sekolah.sch.id/exam/12';

    test('allows exact exam host, subdomain, and trusted embed hosts over HTTPS', () {
      expect(UrlExamPlayer.isUrlAllowed('https://cbt.sekolah.sch.id/page/2', examUrl), isTrue);
      expect(UrlExamPlayer.isUrlAllowed('https://cdn.cbt.sekolah.sch.id/img.png', examUrl), isTrue);
      expect(UrlExamPlayer.isUrlAllowed('https://docs.google.com/forms/d/e/test/viewform', examUrl), isTrue);
      expect(UrlExamPlayer.isUrlAllowed('https://forms.gle/abc123', examUrl), isTrue);
    });

    test('blocks lookalike suffix domains, arbitrary S3, public HTTP, and dangerous schemes', () {
      expect(UrlExamPlayer.isUrlAllowed('https://evilgoogle.com/phish', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('https://attacker-bucket.s3.amazonaws.com/cheat', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('http://docs.google.com/forms', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('javascript:alert(1)', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('file:///etc/passwd', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('intent://scan/#Intent;end', examUrl), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('javascript:alert(1)', examUrl, isMainFrame: false), isFalse);
      expect(UrlExamPlayer.isUrlAllowed('http://evil.com/pixel.png', examUrl, isMainFrame: false), isFalse);
    });

    test('allows local LAN exam servers over HTTP', () {
      const lanExam = 'http://192.168.1.25:8080/ujian';
      expect(UrlExamPlayer.isUrlAllowed('http://192.168.1.25:8080/soal/1', lanExam), isTrue);
      expect(UrlExamPlayer.isUrlAllowed('http://192.168.1.25:8080/audio/1.mp3', lanExam, isMainFrame: false), isTrue);
    });
  });
}

