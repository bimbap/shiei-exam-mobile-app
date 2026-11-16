import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

/// Structured legal clause entry for SHIEI Exam Pro.
class ProLegalSection {
  final String title;
  final String body;

  const ProLegalSection({
    required this.title,
    required this.body,
  });
}

/// Dedicated Terms of Service & Privacy Policy document viewer for SHIEI Exam Pro.
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String effectiveLabel;
  final List<ProLegalSection> sections;
  final IconData icon;
  final Color accentColor;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.effectiveLabel,
    required this.sections,
    required this.icon,
    this.accentColor = AppTheme.primaryGlow,
  });

  static const List<ProLegalSection> termsSections = [
    ProLegalSection(
      title: '1. Penerimaan Ketentuan & Ruang Lingkup Institusi',
      body:
          'Dengan menggunakan aplikasi SHIEI Exam (Edisi Sekolah/Pro), peserta didik, pengawas, dan administrator sekolah menyetujui seluruh Ketentuan Layanan ini. Aplikasi dioperasikan bersama server ujian milik institusi/sekolah masing-masing.',
    ),
    ProLegalSection(
      title: '2. Akun Resmi & Penguncian Perangkat (Hardware Binding)',
      body:
          '• Peserta ujian wajib masuk menggunakan akun resmi dan token ujian yang diterbitkan oleh administrator sekolah.\n'
          '• Sistem mengikat akun ke pengidentifikasi perangkat (Hardware Serial Binding) untuk mencegah praktik perjokian atau penggunaan satu akun di beberapa perangkat secara bersamaan.',
    ),
    ProLegalSection(
      title: '3. Aturan Mode Kiosk & Pengawasan Real-Time',
      body:
          '• Selama ujian berlangsung, perangkat dikunci dalam mode layar penuh/tersemat (Screen Pinning / Guided Access), anti-tangkapan layar, pencegahan jendela mengambang, dan kunci orientasi.\n'
          '• Peringatan panggilan masuk ditangani sesuai kebijakan pengawas dan log sesi ujian.',
    ),
    ProLegalSection(
      title: '4. Pelanggaran Integritas & Pelaporan ke Pengawas',
      body:
          '• Upaya berpindah aplikasi, membuka split-screen, menghubungkan layar eksternal, mengaktifkan Bluetooth terlarang, melepas penyematan layar, atau mencoba mengambil tangkapan layar akan langsung mengunci/mereset sesi.\n'
          '• Insiden pelanggaran dicatat otomatis dan dikirim secara real-time ke server sekolah untuk ditindaklanjuti oleh pengawas atau panitia ujian.',
    ),
    ProLegalSection(
      title: '5. Keabsahan Lisensi & Larangan Modifikasi Aplikasi',
      body:
          'Dilarang keras melakukan pembongkaran kode (reverse engineering), modifikasi paket APK/IPA, hooking runtime (Frida/Xposed), pemalsuan lisensi sekolah, atau menyebarkan ulang biner yang telah diubah tanpa izin tertulis.',
    ),
    ProLegalSection(
      title: '6. Pengelolaan Server Sekolah & Koneksi Lokal',
      body:
          'Ketersediaan soal, nilai akhir, jadwal sesi, dan keandalan jaringan LAN/internet sekolah dikelola sepenuhnya oleh administrator IT atau panitia ujian di institusi penyelenggara.',
    ),
    ProLegalSection(
      title: '7. Hak Kekayaan Intelektual',
      body:
          'Nama merek "Project SHIEI", "SHIEI Exam", desain antarmuka, serta seluruh perangkat lunak klien maupun panelnya dilindungi hak kekayaan intelektual pengembang.',
    ),
    ProLegalSection(
      title: '8. Batasan Tanggung Jawab & Pembaruan',
      body:
          'Pengembang tidak bertanggung jawab atas gangguan perangkat pengguna, daya baterai habis, atau kesalahan konfigurasi server lokal sekolah. Ketentuan ini dapat diperbarui mengikuti rilis aplikasi terbaru di shiei.hexadev.my.id.',
    ),
  ];

  static const List<ProLegalSection> privacySections = [
    ProLegalSection(
      title: '1. Pengelola Data & Peran Server Sekolah (Self-Hosted)',
      body:
          'SHIEI Exam Pro bekerja terhubung langsung ke server ujian mandiri yang dikelola oleh sekolah/institusi Anda. Seluruh data peserta, nilai, dan log pengawasan berada di infrastruktur sekolah penyelenggara.',
    ),
    ProLegalSection(
      title: '2. Data Identitas & Verifikasi Perangkat yang Diproses',
      body:
          '• Kredensial login siswa, status sesi ujian, serta ID serial perangkat diproses untuk otentikasi ujian dan pencegahan joki.\n'
          '• Informasi tipe perangkat, model hardware, dan status kesiapan keamanan ditampilkan di layar Pengaturan dan diperiksa saat diagnostik pra-ujian.',
    ),
    ProLegalSection(
      title: '3. Transparansi Izin Perangkat',
      body:
          '• Kamera (CAMERA): Hanya dipakai saat memindai kode QR konfigurasi/ujian sekolah secara real-time tanpa menyimpan rekaman foto/video.\n'
          '• Jaringan & Status Telepon: Digunakan untuk koneksi ke server sekolah, sinkronisasi waktu ujian, dan mendeteksi panggilan telepon aktif demi pencegahan joki suara.\n'
          '• Audio, Bluetooth & Wake Lock: Menjaga layar tetap aktif saat ujian, memverifikasi perangkat nirkabel nonaktif, dan memutar sirene peringatan bila terjadi pelanggaran.',
    ),
    ProLegalSection(
      title: '4. Tanpa Iklan & Tanpa Pelacakan Perilaku Komersial',
      body:
          'Aplikasi ini bebas SDK iklan pihak ketiga, tidak menjual data siswa, tidak melacak lokasi GPS di luar kebutuhan ujian, serta tidak mengumpulkan daftar kontak atau pesan pribadi.',
    ),
    ProLegalSection(
      title: '5. Penyimpanan Sesi & Pembersihan Browser Ujian',
      body:
          'Token otentikasi disimpan menggunakan penyimpanan aman terenkripsi di perangkat, sementara cache dan cookies peramban soal dibersihkan otomatis saat sesi berakhir atau dihentikan.',
    ),
    ProLegalSection(
      title: '6. Retensi Data & Permintaan Penghapusan',
      body:
          'Kebijakan retensi dan penghapusan data siswa pada server ujian mengikuti ketentuan tata kelola data institusi/sekolah masing-masing. Untuk data preferensi lokal aplikasi, penghapusan permanen terjadi saat logout/uninstall.',
    ),
    ProLegalSection(
      title: '7. Perlindungan Privasi Pelajar & Keamanan Transmisi',
      body:
          'Pertukaran token dan laporan pengawasan antara aplikasi klien dan server sekolah menggunakan validasi integritas sesi untuk menjaga kerahasiaan data peserta didik.',
    ),
    ProLegalSection(
      title: '8. Kontak Dukungan Hukum & Privasi',
      body:
          'Untuk pertanyaan teknis maupun klarifikasi kepatuhan privasi sekolah, hubungi pengembang melalui contact@hexadev.my.id atau kunjungi https://shiei.hexadev.my.id.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final innerBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        centerTitle: true,
        title: Text(title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(icon, color: accentColor, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: bodyColor,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              effectiveLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: bodyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...sections.map(
                (section) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.body,
                        style: TextStyle(
                          fontSize: 12.8,
                          height: 1.55,
                          color: bodyColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kontak Resmi Hukum & Privasi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'HexaDev / Project SHIEI · contact@hexadev.my.id · https://shiei.hexadev.my.id',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: bodyColor,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
