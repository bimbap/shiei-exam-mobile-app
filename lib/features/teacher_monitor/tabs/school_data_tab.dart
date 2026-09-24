import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_notification.dart';
import '../../../shared/widgets/shiei_select_sheet.dart';
import '../../../shared/widgets/shiei_checkbox.dart';
import '../../../shared/widgets/shiei_animated_counter.dart';
import '../../../shared/widgets/shiei_empty_state.dart';
import '../../../shared/widgets/shiei_skeleton.dart';
import '../detail/class_detail_screen.dart';
import '../detail/student_detail_screen.dart';
import '../detail/staff_detail_screen.dart';
import '../dialogs/bulk_add_dialog.dart';
import '../dialogs/class_form_dialog.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../dialogs/user_form_dialog.dart';
import '../teacher_portal_controller.dart';
import '../../tour/proctor_tour_dialog.dart';

class SchoolDataTab extends StatefulWidget {
  final TeacherPortalController controller;
  final ProctorTourTargetKeys? tourKeys;

  const SchoolDataTab({
    super.key,
    required this.controller,
    this.tourKeys,
  });

  @override
  State<SchoolDataTab> createState() => SchoolDataTabState();
}

class SchoolDataTabState extends State<SchoolDataTab> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  /// Handles internal back navigation hierarchically within SchoolDataTab.
  /// Returns true if an internal layer was dismissed/reverted, false if at base state.
  bool handleBackNavigation() {
    // 1. Close speed dial if open
    if (_isSpeedDialOpen) {
      _closeSpeedDial();
      return true;
    }

    // 2. Exit selection mode if active
    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        _selectedIds.clear();
      });
      return true;
    }

    // 3. Clear search query if active
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      widget.controller.setDataSearchQuery('');
      return true;
    }

    return false;
  }

  AnimationController? _speedDialController;
  AnimationController get _effectiveSpeedDialController {
    return _speedDialController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }
  bool _isSpeedDialOpen = false;
  OverlayEntry? _speedDialOverlayEntry;
  final GlobalKey _fabKey = GlobalKey();

  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  List<String> get _categories {
    return widget.controller.isAdmin
        ? const ['students', 'teachers', 'classes', 'users']
        : const ['students', 'teachers', 'classes'];
  }

  PageController? _pageController;
  PageController get _effectivePageController {
    if (_pageController == null) {
      int initialPage = _categories.indexOf(widget.controller.dataCategory);
      if (initialPage < 0) initialPage = 0;
      _pageController = PageController(initialPage: initialPage);
    }
    return _pageController!;
  }
  final ScrollController _categoryScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.controller.dataSearchQuery;
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _speedDialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 180),
    );

    int initialPage = _categories.indexOf(widget.controller.dataCategory);
    if (initialPage < 0) initialPage = 0;
    _pageController = PageController(initialPage: initialPage);
    widget.controller.addListener(_syncPageFromController);
  }

  @override
  void didUpdateWidget(covariant SchoolDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPageFromController);
      widget.controller.addListener(_syncPageFromController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPageFromController);
    if (_speedDialOverlayEntry != null) {
      _speedDialOverlayEntry?.remove();
      _speedDialOverlayEntry = null;
    }
    _speedDialController?.dispose();
    _pageController?.dispose();
    _categoryScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _syncPageFromController() {
    if (!mounted || !_effectivePageController.hasClients) return;
    final currentCat = widget.controller.dataCategory;
    final targetPage = _categories.indexOf(currentCat);
    if (targetPage >= 0 && _effectivePageController.page?.round() != targetPage) {
      _effectivePageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
      _scrollToCategoryPill(targetPage);
    }
  }

  void _scrollToCategoryPill(int index) {
    if (!_categoryScrollController.hasClients) return;
    final targetOffset = (index * 115.0) - 16.0;
    _categoryScrollController.animateTo(
      targetOffset.clamp(0.0, _categoryScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleSpeedDial() {
    HapticFeedback.selectionClick();
    if (_isSpeedDialOpen) {
      _closeSpeedDial();
    } else {
      _openSpeedDial();
    }
  }

  void _openSpeedDial() {
    if (_isSpeedDialOpen) return;

    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final fabOffset = renderBox.localToGlobal(Offset.zero);
    final Size fabSize = renderBox.size;
    final isDark = AppTheme.isDark(context);
    var activeCategory = widget.controller.dataCategory;
    if (!widget.controller.isAdmin && activeCategory == 'users') {
      activeCategory = 'students';
    }
    final items = _getSpeedDialItems(isDark, activeCategory);
    if (items.isEmpty) return;

    setState(() => _isSpeedDialOpen = true);

    final ctrl = _effectiveSpeedDialController;
    _speedDialOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return _SpeedDialOverlayWidget(
          animation: ctrl.view,
          isDark: isDark,
          fabOffset: fabOffset,
          fabSize: fabSize,
          category: activeCategory,
          items: items,
          onClose: () => _closeSpeedDial(),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_speedDialOverlayEntry!);
    ctrl.forward();
  }

  Future<void> _closeSpeedDial({bool immediate = false}) async {
    if (!_isSpeedDialOpen) return;
    if (immediate) {
      _speedDialController?.reset();
      _speedDialOverlayEntry?.remove();
      _speedDialOverlayEntry = null;
      if (mounted) setState(() => _isSpeedDialOpen = false);
      return;
    }
    await _speedDialController?.reverse();
    _speedDialOverlayEntry?.remove();
    _speedDialOverlayEntry = null;
    if (mounted) setState(() => _isSpeedDialOpen = false);
  }

  void _enterSelectionMode(int id) {
    if (_isSpeedDialOpen) _closeSpeedDial();
    HapticFeedback.heavyImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(String category) {
    HapticFeedback.lightImpact();
    List<dynamic> items;
    if (category == 'students') {
      items = widget.controller.filteredStudents;
    } else if (category == 'teachers') {
      items = widget.controller.filteredTeachers;
    } else if (category == 'users') {
      items = widget.controller.filteredUsers;
    } else {
      items = [];
    }

    final allIds = items
        .map((e) => e['id'] is int ? e['id'] as int : int.tryParse(e['id'].toString()))
        .whereType<int>()
        .where((id) {
          if ((category == 'teachers' || category == 'users') && widget.controller.currentUser?['id'] == id) {
            return false;
          }
          return true;
        })
        .toSet();

    setState(() {
      if (_selectedIds.containsAll(allIds)) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(allIds);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmBulkDelete(BuildContext context, String category) async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    String categoryLabel;
    if (category == 'students') {
      categoryLabel = 'Siswa';
    } else if (category == 'teachers') {
      categoryLabel = 'Guru & Staf';
    } else {
      categoryLabel = 'Pengguna';
    }

    final confirmed = await ConfirmDeleteDialog.show(
      context: context,
      title: 'Hapus $count $categoryLabel Terpilih?',
      itemName: '$count data $categoryLabel terpilih',
      message: 'Semua akun dan riwayat terkait $count $categoryLabel yang dipilih akan dihapus secara permanen dari server.',
      confirmLabel: 'Hapus Massal',
      onConfirm: () async {
        final idsList = _selectedIds.toList();
        String? err;
        if (category == 'students') {
          err = await widget.controller.bulkDeleteStudents(idsList);
        } else if (category == 'teachers') {
          err = await widget.controller.bulkDeleteTeachers(idsList);
        } else {
          err = await widget.controller.bulkDeleteUsers(idsList);
        }
        return err;
      },
    );

    if (confirmed == true) {
      _exitSelectionMode();
      if (context.mounted) {
        AppNotification.showSuccess(
          context,
          'Berhasil menghapus $count data $categoryLabel sekaligus.',
        );
      }
    }
  }

  void _confirmResetDevice(BuildContext context, Map<String, dynamic> student) {
    final isDark = AppTheme.isDark(context);
    final studentId = student['id'];
    final studentName = student['name'] ?? 'Siswa';
    final deviceModel = student['device_name'] ?? student['serial_number'] ?? 'Perangkat Terdaftar';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF8B5CF6), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Reset Binding HP?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Lepaskan kunci perangkat untuk "$studentName"?\n\n'
          'Perangkat saat ini: $deviceModel\n\n'
          'Setelah di-reset, siswa dapat langsung login menggunakan HP cadangan atau perangkat baru.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (studentId != null) {
                final ok = await widget.controller.resetStudentDevice(studentId);
                if (context.mounted) {
                  if (ok) {
                    AppNotification.showSuccess(
                      context,
                      'Device Berhasil Direset',
                      subtitle: '$studentName sekarang bisa login di HP baru.',
                    );
                  } else {
                    AppNotification.showError(
                      context,
                      'Gagal Mereset Perangkat',
                      subtitle: 'Tidak dapat melepaskan kunci perangkat dari server.',
                    );
                  }
                }
              }
            },
            child: const Text('Reset Kunci HP'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTeacherDetailModal(BuildContext context, Map<String, dynamic> teacher) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return;

    final isDark = AppTheme.isDark(context);
    final name = teacher['name']?.toString() ?? 'Guru';
    final nip = teacher['nip']?.toString() ?? '-';
    final email = teacher['email']?.toString() ?? '-';
    final rawUsername = teacher['username']?.toString().trim();
    final username = (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
        ? rawUsername
        : (name.isNotEmpty && name != 'Guru' ? name : '-');
    final subRole = teacher['sub_role']?.toString() ?? 'guru';
    final classMajor = teacher['class_major']?['name']?.toString();

    String subRoleLabel;
    Color subRoleColor;
    switch (subRole.toLowerCase()) {
      case 'kepala_sekolah':
        subRoleLabel = 'Kepala Sekolah';
        subRoleColor = const Color(0xFF6366F1);
        break;
      case 'wakil_kepala_sekolah':
        subRoleLabel = 'Wakil Kepala Sekolah';
        subRoleColor = const Color(0xFF3B82F6);
        break;
      case 'karyawan':
        subRoleLabel = 'Karyawan / Staf TU';
        subRoleColor = const Color(0xFFF59E0B);
        break;
      default:
        subRoleLabel = 'Guru Pengajar';
        subRoleColor = const Color(0xFF10B981);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: subRoleColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'G',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: subRoleColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: subRoleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: subRoleColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            subRoleLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: subRoleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 1,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 12),
              _buildInfoRow('NIP Pegawai', nip, Icons.badge_outlined, isDark),
              _buildInfoRow('Alamat Email', email, Icons.email_outlined, isDark),
              _buildInfoRow('Username', username, Icons.person_outline_rounded, isDark),
              if (classMajor != null && classMajor.isNotEmpty)
                _buildInfoRow('Wali Kelas', classMajor, Icons.meeting_room_outlined, isDark, isClassBadge: true),
              _buildInfoRow('Status Akun', 'Aktif', Icons.verified_user_outlined, isDark, valueColor: const Color(0xFF10B981)),
              const SizedBox(height: 16),
              if (widget.controller.isAdmin) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: subRoleColor,
                          side: BorderSide(color: subRoleColor.withValues(alpha: 0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(
                          subRole.toLowerCase() == 'karyawan' ? 'Edit Staf' : 'Edit Guru',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          UserFormDialog.show(
                            context: context,
                            userData: teacher,
                            initialRole: 'teacher',
                            controller: widget.controller,
                          );
                        },
                      ),
                    ),
                    if (widget.controller.currentUser?['id'] != teacher['id']) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFFEF4444),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        tooltip: 'Hapus Guru',
                        onPressed: () {
                          Navigator.pop(ctx);
                          ConfirmDeleteDialog.show(
                            context: context,
                            title: 'Hapus Akun Guru & Staf?',
                            itemName: name,
                            message: 'Akun guru ini dan riwayat penugasan akan dihapus secara permanen.',
                            onConfirm: () => widget.controller.deleteUser(teacher['id']),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: subRoleColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    subRole.toLowerCase() == 'karyawan' ? 'Detail Staf' : 'Detail Guru',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StaffDetailScreen(
                          staff: teacher,
                          controller: widget.controller,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
}

  Future<void> _showUserDetailModal(BuildContext context, Map<String, dynamic> user) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return;

    final isDark = AppTheme.isDark(context);
    final name = user['name']?.toString() ?? 'Pengguna';
    final role = user['role']?.toString().toLowerCase() ?? 'student';
    final email = user['email']?.toString() ?? '-';
    final rawUsername = user['username']?.toString().trim();
    final username = (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
        ? rawUsername
        : (name.isNotEmpty && name != 'Pengguna' ? name : '-');
    final nip = user['nip']?.toString();
    final nisn = user['nisn']?.toString();
    final className = user['class_major']?['name']?.toString() ?? user['classes']?['name']?.toString();
    final isStudent = role == 'student';

    String roleLabel;
    Color roleColor;
    IconData roleIcon;
    switch (role) {
      case 'school_admin':
        roleLabel = 'Admin Sekolah';
        roleColor = const Color(0xFFF59E0B);
        roleIcon = Icons.admin_panel_settings_rounded;
        break;
      case 'teacher':
        roleLabel = 'Guru & Staf';
        roleColor = const Color(0xFF10B981);
        roleIcon = Icons.badge_rounded;
        break;
      default:
        roleLabel = 'Siswa';
        roleColor = const Color(0xFF8B5CF6);
        roleIcon = Icons.school_rounded;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(roleIcon, color: roleColor, size: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            roleLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: roleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 1,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 12),
              _buildInfoRow('Peran Akun', roleLabel, Icons.shield_outlined, isDark),
              _buildInfoRow('Username', username, Icons.account_circle_outlined, isDark),
              if (!isStudent)
                _buildInfoRow('Email', (email != '-' && email.isNotEmpty) ? email : 'Tidak ada', Icons.email_outlined, isDark),
              if (isStudent) ...[
                _buildInfoRow('NISN Siswa', (nisn != null && nisn.isNotEmpty && nisn != '-') ? nisn : '-', Icons.tag_rounded, isDark),
                _buildInfoRow(
                  'Kelas',
                  (className != null && className.isNotEmpty && className != '-') ? className : 'Belum Ditentukan',
                  Icons.meeting_room_outlined,
                  isDark,
                  isClassBadge: (className != null && className.isNotEmpty && className != '-'),
                ),
              ] else ...[
                _buildInfoRow('NIP Pegawai', (nip != null && nip.isNotEmpty && nip != '-') ? nip : '-', Icons.badge_outlined, isDark),
                if (className != null && className.isNotEmpty && className != '-')
                  _buildInfoRow('Wali Kelas', className, Icons.meeting_room_outlined, isDark, isClassBadge: true),
              ],
              const SizedBox(height: 16),
              if (widget.controller.isAdmin) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: roleColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Akun', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          UserFormDialog.show(
                            context: context,
                            userData: user,
                            controller: widget.controller,
                          );
                        },
                      ),
                    ),
                    if (widget.controller.currentUser?['id'] != user['id']) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFFEF4444),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        tooltip: 'Hapus Akun',
                        onPressed: () {
                          Navigator.pop(ctx);
                          ConfirmDeleteDialog.show(
                            context: context,
                            title: 'Hapus Akun Pengguna?',
                            itemName: name,
                            message: 'Akun ini akan dihapus secara permanen dari sekolah.',
                            onConfirm: () => widget.controller.deleteUser(user['id']),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (isStudent) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(
                            color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.7 : 0.8),
                          ),
                          foregroundColor: const Color(0xFFF59E0B),
                        ),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Mutasi Kelas', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showMutasiKelasDialog(context, user, isDark);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Detail Siswa', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentDetailScreen(
                                student: user,
                                controller: widget.controller,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: roleColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      role == 'school_admin' ? 'Detail Administrator' : 'Detail Guru & Staf',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StaffDetailScreen(
                            staff: user,
                            controller: widget.controller,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
}

  Future<void> _showMutasiKelasDialog(BuildContext context, Map<String, dynamic> student, bool isDark) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return;

    final studentId = student['id'];
    if (studentId == null) return;

    final currentClassId = student['class_major_id'] ??
        student['class_id'] ??
        student['class_major']?['id'];
    final currentClassName = student['class_major']?['name']?.toString() ??
        student['classes']?['name']?.toString() ??
        student['class_name']?.toString() ??
        'Tanpa Kelas';
    final studentName = student['name']?.toString() ?? 'Siswa';

    int? targetClassId;
    bool isSubmitting = false;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
            final availableClasses = widget.controller.classes;

            return Container(
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF59E0B), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mutasi / Pindah Kelas',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Pindahkan "$studentName" ke kelas baru',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (localError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                localError!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Current Class Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.meeting_room_outlined, size: 18, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kelas Saat Ini',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  currentClassName,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Destination Class Selector
                    ShieiSelectorField<int>(
                      label: 'Pilih Kelas Tujuan Baru *',
                      isDark: isDark,
                      prefixIcon: Icons.login_rounded,
                      valueText: targetClassId == null
                          ? 'Pilih Kelas Tujuan Mutasi'
                          : availableClasses.firstWhere(
                              (c) => c['id'] == targetClassId,
                              orElse: () => {'name': 'Kelas #$targetClassId'},
                            )['name'],
                      onTap: () async {
                        final otherClasses = availableClasses.where((c) {
                          if (currentClassId == null) return true;
                          return c['id'].toString() != currentClassId.toString();
                        }).toList();

                        final selected = await ShieiSelectSheet.show<int>(
                          context: context,
                          title: 'Pilih Kelas Tujuan Mutasi',
                          subtitle: 'Pilih kelas baru untuk siswa ini',
                          selectedValue: targetClassId,
                          items: otherClasses.map((c) {
                            return ShieiSelectItem<int>(
                              value: c['id'] as int,
                              label: c['name']?.toString() ?? 'Kelas',
                              subtitle: 'Kelas Sekolah',
                              icon: Icons.school_rounded,
                            );
                          }).toList(),
                        );
                        if (selected != null) {
                          setModalState(() {
                            targetClassId = selected;
                            localError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            ),
                            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                            child: Text(
                              'Batal',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    if (targetClassId == null) {
                                      setModalState(() {
                                        localError = 'Pilih kelas tujuan mutasi terlebih dahulu.';
                                      });
                                      return;
                                    }

                                    setModalState(() {
                                      isSubmitting = true;
                                      localError = null;
                                    });

                                    final int sId = (studentId is int) ? studentId : int.parse(studentId.toString());
                                    final err = await widget.controller.transferStudentClass(
                                      sId,
                                      targetClassId!,
                                    );

                                    if (err == null) {
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      final targetClass = availableClasses.firstWhere(
                                        (c) => c['id'] == targetClassId,
                                        orElse: () => {'name': 'Kelas #$targetClassId'},
                                      );
                                      if (context.mounted) {
                                        AppNotification.showSuccess(
                                          context,
                                          'Mutasi Siswa Berhasil',
                                          subtitle: '$studentName berhasil dipindahkan ke ${targetClass['name']}.',
                                        );
                                      }
                                    } else {
                                      if (modalCtx.mounted) {
                                        setModalState(() {
                                          isSubmitting = false;
                                          localError = err;
                                        });
                                      }
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Proses Mutasi Kelas',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
}

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    bool isDark, {
    Color? valueColor,
    bool isClassBadge = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
          const Spacer(),
          if (isClassBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.4 : 0.25),
                  width: 0.8,
                ),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B5CF6),
                ),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    var activeCategory = widget.controller.dataCategory;

    // Strict role alignment:
    // Teachers can view categorized data (students, teachers, classes) but 'users' (Semua User) is strictly Admin only
    if (!widget.controller.isAdmin && activeCategory == 'users') {
      activeCategory = 'students';
    }

    final bool canAdd = widget.controller.isAdmin || (activeCategory == 'students' && widget.controller.canAddStudent);

    return Stack(
      children: [
        Column(
          children: [
            // 1. Top Category Bar (Siswa, Guru, Semua User, Kelas)
            _buildCategoryHeader(isDark, activeCategory),

            // 2. Dynamic Search Bar (Clean header - top add banner removed)
            _buildSearchBar(isDark, activeCategory),

            // 3. Sub-Filters Chips (Contextual per category)
            _buildSubFilters(isDark, activeCategory),

            // 4. Content Area (Swipeable PageView)
            Expanded(
              child: PageView(
                controller: _effectivePageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (pageIndex) {
                  final cats = _categories;
                  if (pageIndex >= 0 && pageIndex < cats.length) {
                    final cat = cats[pageIndex];
                    if (_isSelectionMode) {
                      _exitSelectionMode();
                    }
                    widget.controller.setDataCategory(cat);
                    _scrollToCategoryPill(pageIndex);
                  }
                },
                children: [
                  _buildStudentsView(isDark),
                  _buildTeachersView(isDark),
                  _buildClassesView(isDark),
                  if (widget.controller.isAdmin) _buildUsersView(isDark),
                ],
              ),
            ),
          ],
        ),

        // 5. Google Drive Style Speed Dial FAB (Hidden in selection mode)
        if (!_isSelectionMode && canAdd)
          Positioned(
            right: 18,
            bottom: 24,
            child: _buildSpeedDialFab(isDark, activeCategory),
          ),

        // 8. Floating Multi-Selection Action Bar (Contextual by selection count)
        if (_isSelectionMode && activeCategory != 'classes')
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildSelectionActionBar(isDark, activeCategory),
          ),
      ],
    );
  }

  // --- FLOATING MULTI-SELECTION ACTION BAR (CONDITIONAL: 1 vs >1) ---
  Widget _buildSelectionActionBar(bool isDark, String category) {
    final count = _selectedIds.length;
    final primaryColor = category == 'students'
        ? const Color(0xFF8B5CF6)
        : (category == 'teachers' ? const Color(0xFF10B981) : const Color(0xFF3B82F6));

    final categoryLabel = category == 'students'
        ? 'Siswa'
        : (category == 'teachers' ? 'Guru/Staf' : 'Pengguna');

    // === CONDITION 1: EXACTLY 1 ITEM SELECTED (Contextual Single Actions) ===
    if (count == 1) {
      final singleId = _selectedIds.first;
      Map<String, dynamic>? item;
      if (category == 'students') {
        item = widget.controller.students.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['id'] == singleId,
          orElse: () => null,
        );
      } else if (category == 'teachers') {
        item = widget.controller.teachers.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['id'] == singleId,
          orElse: () => null,
        );
      } else if (category == 'users') {
        item = widget.controller.allUsers.cast<Map<String, dynamic>?>().firstWhere(
          (u) => u?['id'] == singleId,
          orElse: () => null,
        );
      }

      final itemName = item?['name']?.toString() ?? '1 $categoryLabel';
      final hasBound = item != null &&
          ((item['device_name'] != null && item['device_name'].toString().isNotEmpty) ||
              (item['serial_number'] != null && item['serial_number'].toString().isNotEmpty));
      final isSelf = widget.controller.currentUser?['id'] == singleId;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Dismiss, Item Name, and "Pilih Semua"
            Row(
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: _exitSelectionMode,
                  tooltip: 'Batal',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      ShieiAnimatedCounter(
                        count: 1,
                        suffix: ' $categoryLabel Terpilih',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectAll(category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist_rounded, size: 14, color: primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          'Pilih Semua',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Bottom row: Contextual Action Buttons for this 1 item
            Row(
              children: [
                // 1. Edit Data
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (item == null) return;
                        _exitSelectionMode();
                        if (category == 'students') {
                          UserFormDialog.show(
                            context: context,
                            userData: item,
                            initialRole: 'student',
                            controller: widget.controller,
                          );
                        } else if (category == 'teachers') {
                          UserFormDialog.show(
                            context: context,
                            userData: item,
                            initialRole: 'teacher',
                            controller: widget.controller,
                          );
                        } else if (category == 'users') {
                          UserFormDialog.show(
                            context: context,
                            userData: item,
                            controller: widget.controller,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded, size: 15, color: Color(0xFF3B82F6)),
                            SizedBox(width: 5),
                            Text(
                              'Edit Data',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Reset Kunci HP (khusus siswa yang terikat perangkat)
                if (category == 'students' && hasBound) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (item == null) return;
                          _exitSelectionMode();
                          _confirmResetDevice(context, item);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phonelink_erase_rounded, size: 15, color: Color(0xFF8B5CF6)),
                              SizedBox(width: 5),
                              Text(
                                'Reset HP',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // 3. Hapus Item
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isSelf
                          ? null
                          : () {
                              if (item == null) return;
                              _exitSelectionMode();
                              if (category == 'students') {
                                ConfirmDeleteDialog.show(
                                  context: context,
                                  title: 'Hapus Akun Siswa?',
                                  itemName: itemName,
                                  message: 'Data siswa ini dan riwayat ujiannya akan dihapus secara permanen.',
                                  onConfirm: () => widget.controller.deleteUser(singleId),
                                );
                              } else if (category == 'teachers') {
                                ConfirmDeleteDialog.show(
                                  context: context,
                                  title: 'Hapus Akun Guru?',
                                  itemName: itemName,
                                  message: 'Akun guru ini dan riwayat penugasan akan dihapus secara permanen.',
                                  onConfirm: () => widget.controller.deleteUser(singleId),
                                );
                              } else if (category == 'users') {
                                ConfirmDeleteDialog.show(
                                  context: context,
                                  title: 'Hapus Pengguna?',
                                  itemName: itemName,
                                  message: 'Akun ini akan dihapus secara permanen dari server.',
                                  onConfirm: () => widget.controller.deleteUser(singleId),
                                );
                              }
                            },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFEF4444)),
                            const SizedBox(width: 5),
                            Text(
                              isSelf ? 'Anda' : 'Hapus',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // === CONDITION 2: MORE THAN 1 ITEM SELECTED (Batch Actions Only) ===
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(7),
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: _exitSelectionMode,
            tooltip: 'Batal Pilih',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShieiAnimatedCounter(
                  count: count,
                  suffix: ' $categoryLabel Terpilih',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectAll(category),
                  child: Text(
                    'Pilih Semua / Batal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text(
              'Hapus',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            onPressed: count > 0 ? () => _confirmBulkDelete(context, category) : null,
          ),
        ],
      ),
    );
  }

  // --- GOOGLE DRIVE STYLE SPEED DIAL FAB & ROOT OVERLAY FLYOUT ---
  Widget _buildSpeedDialFab(bool isDark, String category) {
    Color fabColor;
    switch (category) {
      case 'teachers':
        fabColor = const Color(0xFF10B981);
        break;
      case 'classes':
        fabColor = const Color(0xFFF59E0B);
        break;
      case 'users':
        fabColor = const Color(0xFF3B82F6);
        break;
      default:
        fabColor = const Color(0xFF8B5CF6);
    }

    return Material(
      key: _fabKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleSpeedDial,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: fabColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: fabColor.withValues(alpha: 0.38),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.add_rounded, size: 28, color: Colors.white),
          ),
        ),
      ),
    );
  }

  List<_SpeedDialItem> _getSpeedDialItems(bool isDark, String category) {
    final List<_SpeedDialItem> items = [];

    if (category == 'students') {
      if (widget.controller.isAdmin || widget.controller.canAddStudent) {
        items.add(_SpeedDialItem(
          label: 'Import Massal (Excel)',
          icon: Icons.table_chart_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            BulkAddDialog.show(context: context, category: 'students', controller: widget.controller);
          },
        ));
        items.add(_SpeedDialItem(
          label: 'Tambah Siswa Manual',
          icon: Icons.person_add_alt_1_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            UserFormDialog.show(
              context: context,
              initialRole: 'student',
              allowRoleChange: false,
              controller: widget.controller,
            );
          },
        ));
      }
    } else if (category == 'teachers') {
      if (widget.controller.isAdmin) {
        items.add(_SpeedDialItem(
          label: 'Import Massal (Excel)',
          icon: Icons.table_chart_rounded,
          color: const Color(0xFF10B981),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            BulkAddDialog.show(context: context, category: 'teachers', controller: widget.controller);
          },
        ));
        items.add(_SpeedDialItem(
          label: 'Tambah Guru / Staf',
          icon: Icons.badge_rounded,
          color: const Color(0xFF10B981),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            UserFormDialog.show(
              context: context,
              initialRole: 'teacher',
              allowRoleChange: false,
              controller: widget.controller,
            );
          },
        ));
      }
    } else if (category == 'classes') {
      if (widget.controller.isAdmin) {
        items.add(_SpeedDialItem(
          label: 'Tambah Kelas Baru',
          icon: Icons.add_home_work_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            ClassFormDialog.show(context: context, controller: widget.controller);
          },
        ));
      }
    } else if (category == 'users') {
      if (widget.controller.isAdmin) {
        items.add(_SpeedDialItem(
          label: 'Import Massal (Excel)',
          icon: Icons.table_chart_rounded,
          color: const Color(0xFF3B82F6),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            BulkAddDialog.show(context: context, category: 'users', controller: widget.controller);
          },
        ));
        items.add(_SpeedDialItem(
          label: 'Tambah Pengguna Baru',
          icon: Icons.person_add_rounded,
          color: const Color(0xFF3B82F6),
          onTap: () async {
            await _closeSpeedDial();
            if (!mounted) return;
            UserFormDialog.show(
              context: context,
              allowRoleChange: true,
              controller: widget.controller,
            );
          },
        ));
      }
    }

    return items;
  }

  // --- 1. TOP CATEGORY HEADER ---
  Widget _buildCategoryHeader(bool isDark, String activeCategory) {
    final studentsCount = widget.controller.students.length;
    final teachersCount = widget.controller.teachers.length;
    final usersCount = widget.controller.allUsers.length;
    final classesCount = widget.controller.classes.length;

    return Container(
      key: widget.tourKeys?.schoolCategoryKey,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: SingleChildScrollView(
        controller: _categoryScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildCategoryPill(
              keyName: 'students',
              title: 'Siswa',
              count: studentsCount,
              icon: Icons.school_rounded,
              color: const Color(0xFF8B5CF6),
              isSelected: activeCategory == 'students',
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _buildCategoryPill(
              keyName: 'teachers',
              title: 'Guru & Staf',
              count: teachersCount,
              icon: Icons.badge_rounded,
              color: const Color(0xFF10B981),
              isSelected: activeCategory == 'teachers',
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _buildCategoryPill(
              keyName: 'classes',
              title: 'Kelas',
              count: classesCount,
              icon: Icons.meeting_room_rounded,
              color: const Color(0xFFF59E0B),
              isSelected: activeCategory == 'classes',
              isDark: isDark,
            ),
            if (widget.controller.isAdmin) ...[
              const SizedBox(width: 8),
              _buildCategoryPill(
                keyName: 'users',
                title: 'Semua User',
                count: usersCount,
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF3B82F6),
                isSelected: activeCategory == 'users',
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPill({
    required String keyName,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isDark,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        HapticFeedback.selectionClick();
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
        widget.controller.setDataCategory(keyName);
        final targetIndex = _categories.indexOf(keyName);
        if (targetIndex >= 0 && _effectivePageController.hasClients) {
          _effectivePageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.14)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? color : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : color)
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ShieiAnimatedCounter(
                count: count,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. SEARCH BAR ---
  Widget _buildSearchBar(bool isDark, String category) {
    String hintText;
    switch (category) {
      case 'teachers':
        hintText = 'Cari guru, NIP, atau jabatan...';
        break;
      case 'users':
        hintText = 'Cari nama, email, NIP, atau NISN...';
        break;
      case 'classes':
        hintText = 'Cari nama kelas...';
        break;
      default:
        hintText = 'Cari siswa atau NISN...';
    }

    final searchField = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        onChanged: (val) {
          widget.controller.setDataSearchQuery(val);
          setState(() {});
        },
        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                splashRadius: 18,
                tooltip: 'Hapus Teks Pencarian',
                onPressed: () {
                  _searchController.clear();
                  widget.controller.setDataSearchQuery('');
                  setState(() {});
                },
              );
            },
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          filled: true,
          fillColor: isDark ? AppTheme.surfaceDark : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: category == 'students'
          ? Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 8),
                _buildClassPickerDropdown(isDark),
              ],
            )
          : searchField,
    );
  }

  Future<void> _showClassFilterBottomSheet(BuildContext context, bool isDark) async {
    final classes = widget.controller.classes;
    final selectedId = widget.controller.selectedClassId;
    final students = widget.controller.students;
    final totalStudents = students.length;

    final items = <ShieiSelectItem<int>>[
      ShieiSelectItem<int>(
        value: -1,
        label: 'Semua Kelas',
        subtitle: '$totalStudents siswa terdaftar',
        icon: Icons.apps_rounded,
        badge: '$totalStudents Siswa',
        badgeColor: const Color(0xFF8B5CF6),
      ),
      ...classes.map((c) {
        final id = c['id'] is int ? c['id'] as int : (int.tryParse(c['id'].toString()) ?? 0);
        final name = c['name']?.toString() ?? 'Kelas';
        final count = students.where((s) {
          final sClassId = s['class_major_id'] ?? s['class_id'] ?? s['class_major']?['id'] ?? s['classes']?['id'];
          return sClassId?.toString() == id.toString();
        }).length;

        return ShieiSelectItem<int>(
          value: id,
          label: name,
          subtitle: '$count siswa terdaftar',
          icon: Icons.school_outlined,
          badge: count > 0 ? '$count Siswa' : 'Kosong',
          badgeColor: count > 0 ? const Color(0xFF8B5CF6) : const Color(0xFF64748B),
        );
      }),
    ];

    final selected = await ShieiSelectSheet.show<int>(
      context: context,
      title: 'Pilih Filter Kelas',
      subtitle: 'Saring daftar siswa berdasarkan kelas',
      icon: Icons.meeting_room_rounded,
      accentColor: const Color(0xFF8B5CF6),
      items: items,
      selectedValue: selectedId ?? -1,
      showSearch: true,
      searchHint: 'Cari nama kelas...',
    );

    if (selected != null && mounted) {
      if (selected == -1) {
        if (selectedId != null) {
          widget.controller.setSelectedClass(null);
        }
      } else {
        if (selected != selectedId) {
          widget.controller.setSelectedClass(selected);
        }
      }
    }
  }

  Widget _buildClassPickerDropdown(bool isDark) {
    final classes = widget.controller.classes;
    final selectedId = widget.controller.selectedClassId;
    final selectedClass = classes.firstWhere(
      (c) => c['id'] == selectedId,
      orElse: () => <String, dynamic>{},
    );
    final isClassSelected = selectedId != null;
    final selectedName = isClassSelected ? (selectedClass['name']?.toString() ?? 'Kelas') : 'Semua Kelas';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        _showClassFilterBottomSheet(context, isDark);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isClassSelected
              ? const Color(0xFF8B5CF6).withOpacity(0.15)
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isClassSelected
                ? const Color(0xFF8B5CF6)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isClassSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room_rounded,
              size: 15,
              color: isClassSelected
                  ? const Color(0xFF8B5CF6)
                  : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                selectedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isClassSelected ? FontWeight.bold : FontWeight.w500,
                  color: isClassSelected
                      ? (isDark ? Colors.white : const Color(0xFF8B5CF6))
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: isClassSelected
                  ? const Color(0xFF8B5CF6)
                  : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 3. SUB FILTERS ROW ---
  Widget _buildSubFilters(bool isDark, String category) {
    if (category == 'students') {
      final currentDeviceFilter = widget.controller.studentDeviceFilter;
      final boundCount = widget.controller.students.where((s) {
        final d = s['device_name']?.toString();
        final ser = s['serial_number']?.toString();
        return (d != null && d.isNotEmpty) || (ser != null && ser.isNotEmpty);
      }).length;
      final unboundCount = widget.controller.students.length - boundCount;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          key: widget.tourKeys?.deviceBindingKey,
          child: Row(
            children: [
              _buildFilterChip(
                label: 'Semua Status',
                isSelected: currentDeviceFilter == 'all',
                color: const Color(0xFF8B5CF6),
                isDark: isDark,
                onTap: () => widget.controller.setStudentDeviceFilter('all'),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                label: '🔒 Terikat HP ($boundCount)',
                isSelected: currentDeviceFilter == 'bound',
                color: const Color(0xFF10B981),
                isDark: isDark,
                onTap: () => widget.controller.setStudentDeviceFilter('bound'),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                label: '🔓 Belum Terikat ($unboundCount)',
                isSelected: currentDeviceFilter == 'unbound',
                color: const Color(0xFFF59E0B),
                isDark: isDark,
                onTap: () => widget.controller.setStudentDeviceFilter('unbound'),
              ),
            ],
          ),
        ),
      );
    } else if (category == 'teachers') {
      final currentSubRole = widget.controller.teacherSubRoleFilter;
      final options = [
        {'id': 'all', 'label': 'Semua Staf'},
        {'id': 'kepala_sekolah', 'label': 'Kepala Sekolah'},
        {'id': 'wakil_kepala_sekolah', 'label': 'Wakil Kepala'},
        {'id': 'guru', 'label': 'Guru Pengajar'},
        {'id': 'karyawan', 'label': 'Karyawan / TU'},
      ];

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            ...options.map((opt) {
              final id = opt['id']!;
              final label = opt['label']!;
              final isSelected = currentSubRole == id;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildFilterChip(
                  label: label,
                  isSelected: isSelected,
                  color: const Color(0xFF10B981),
                  isDark: isDark,
                  onTap: () => widget.controller.setTeacherSubRoleFilter(id),
                ),
              );
            }),
          ],
        ),
      );
    } else if (category == 'users') {
      final currentRole = widget.controller.userRoleFilter;
      final options = [
        {'id': 'all', 'label': 'Semua Peran'},
        {'id': 'school_admin', 'label': 'Admin Sekolah'},
        {'id': 'teacher', 'label': 'Guru & Staf'},
        {'id': 'student', 'label': 'Siswa'},
      ];

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            ...options.map((opt) {
              final id = opt['id']!;
              final label = opt['label']!;
              final isSelected = currentRole == id;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildFilterChip(
                  label: label,
                  isSelected: isSelected,
                  color: const Color(0xFF3B82F6),
                  isDark: isDark,
                  onTap: () => widget.controller.setUserRoleFilter(id),
                ),
              );
            }),
          ],
        ),
      );
    }

    return const SizedBox(height: 2);
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.15)
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : color)
                : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  // --- 4. CONTENT SELECTION ---
  Widget _buildCategoryContent(bool isDark, String category) {
    switch (category) {
      case 'teachers':
        return _buildTeachersView(isDark);
      case 'users':
        return _buildUsersView(isDark);
      case 'classes':
        return _buildClassesView(isDark);
      default:
        return _buildStudentsView(isDark);
    }
  }

  // --- VIEW: SISWA ---
  Widget _buildStudentsView(bool isDark) {
    final students = widget.controller.filteredStudents;
    final isSearch = widget.controller.dataSearchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      color: const Color(0xFF8B5CF6),
      onRefresh: () => widget.controller.loadStudents(clearPrevious: true),
      child: (widget.controller.isLoading || widget.controller.isStudentsLoading)
          ? const ParticipantRowSkeleton(
              count: 6,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
              physics: AlwaysScrollableScrollPhysics(),
            )
          : students.isEmpty
              ? (isSearch
                  ? ShieiEmptyState.searchNotFound(
                      context: context,
                      searchQuery: widget.controller.dataSearchQuery,
                      categoryLabel: 'Siswa',
                      accentColor: const Color(0xFF8B5CF6),
                      isDark: isDark,
                      onClearSearch: () {
                        _searchController.clear();
                        widget.controller.setDataSearchQuery('');
                        setState(() {});
                      },
                    )
                  : ShieiEmptyState(
                      title: 'Belum Ada Siswa Terdaftar',
                      message: 'Database siswa masih kosong. Mulai tambahkan siswa secara manual atau import massal via template Excel.',
                      icon: Icons.school_outlined,
                      accentColor: const Color(0xFF8B5CF6),
                      isDark: isDark,
                      primaryActionLabel: '+ Tambah Siswa Manual',
                      onPrimaryAction: () => UserFormDialog.show(
                        context: context,
                        initialRole: 'student',
                        allowRoleChange: false,
                        controller: widget.controller,
                      ),
                      secondaryActionLabel: 'Import Massal via Excel',
                      onSecondaryAction: () => BulkAddDialog.show(context: context, category: 'students', controller: widget.controller),
                    ))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: students.length,
                  itemBuilder: (ctx, index) {
                    final student = students[index];
                    return _buildStudentItemCard(ctx, student, isDark);
                  },
                ),
    );
  }

  Widget _buildStudentItemCard(BuildContext context, Map<String, dynamic> student, bool isDark) {
    final studentId = student['id'] is int ? student['id'] as int : int.tryParse(student['id'].toString()) ?? 0;
    final isSelected = _selectedIds.contains(studentId);

    final name = student['name']?.toString() ?? 'Siswa';
    final rawNisn = student['nisn']?.toString().trim();
    final rawUsername = student['username']?.toString().trim();
    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
        ? rawNisn
        : (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
            ? rawUsername
            : '-';
    final className = student['class_major']?['name']?.toString() ??
        student['classes']?['name']?.toString() ??
        student['class_name']?.toString() ??
        'Umum';
    final deviceName = student['device_name']?.toString();
    final serial = student['serial_number']?.toString();
    final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.15 : 0.08)
            : (isDark ? AppTheme.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF8B5CF6)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(studentId);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentDetailScreen(
                  student: student,
                  controller: widget.controller,
                ),
              ),
            );
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(studentId);
            } else {
              _toggleSelection(studentId);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _isSelectionMode
                      ? Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ShieiCheckbox(
                            value: isSelected,
                            activeColor: const Color(0xFF8B5CF6),
                            onChanged: (_) => _toggleSelection(studentId),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasBoundDevice
                        ? const Color(0xFF8B5CF6).withOpacity(0.12)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: hasBoundDevice ? const Color(0xFF8B5CF6) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Line 1: Kelas
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.16 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.35 : 0.22),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.school_outlined, size: 11.5, color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 4),
                            Text(
                              'Kelas $className',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8B5CF6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Line 2: NISN
                      Text(
                        'NISN: $nisn',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            hasBoundDevice ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                            size: 13,
                            color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hasBoundDevice ? '${deviceName ?? serial}' : 'Belum terikat ke perangkat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: hasBoundDevice
                                    ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                    : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                                fontWeight: hasBoundDevice ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (hasBoundDevice)
                  IconButton(
                    icon: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF8B5CF6), size: 20),
                    tooltip: 'Reset Binding HP',
                    onPressed: () => _confirmResetDevice(context, student),
                  )
                else
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFCBD5E1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- VIEW: GURU & STAF ---
  // --- VIEW: GURU & STAF ---
  Widget _buildTeachersView(bool isDark) {
    final teachers = widget.controller.filteredTeachers;
    final isSearch = widget.controller.dataSearchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      color: const Color(0xFF10B981),
      onRefresh: () => widget.controller.loadTeachers(clearPrevious: true),
      child: (widget.controller.isLoading || widget.controller.isTeachersLoading)
          ? const ParticipantRowSkeleton(
              count: 6,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
              physics: AlwaysScrollableScrollPhysics(),
            )
          : teachers.isEmpty
              ? (isSearch
                  ? ShieiEmptyState.searchNotFound(
                      context: context,
                      searchQuery: widget.controller.dataSearchQuery,
                      categoryLabel: 'Guru & Staf',
                      accentColor: const Color(0xFF10B981),
                      isDark: isDark,
                      onClearSearch: () {
                        _searchController.clear();
                        widget.controller.setDataSearchQuery('');
                        setState(() {});
                      },
                    )
                  : ShieiEmptyState(
                      title: 'Belum Ada Guru & Staf',
                      message: 'Belum ada data pengajar yang terdaftar. Tambahkan guru pengajar atau import massal via template Excel.',
                      icon: Icons.badge_outlined,
                      accentColor: const Color(0xFF10B981),
                      isDark: isDark,
                      primaryActionLabel: '+ Tambah Guru / Staf',
                      onPrimaryAction: () => UserFormDialog.show(
                        context: context,
                        initialRole: 'teacher',
                        allowRoleChange: false,
                        controller: widget.controller,
                      ),
                      secondaryActionLabel: 'Import Massal via Excel',
                      onSecondaryAction: () => BulkAddDialog.show(context: context, category: 'teachers', controller: widget.controller),
                    ))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: teachers.length,
                  itemBuilder: (ctx, index) {
                    final teacher = teachers[index];
                    return _buildTeacherItemCard(ctx, teacher, isDark);
                  },
                ),
    );
  }

  Widget _buildTeacherItemCard(BuildContext context, Map<String, dynamic> teacher, bool isDark) {
    final teacherId = teacher['id'] is int ? teacher['id'] as int : int.tryParse(teacher['id'].toString()) ?? 0;
    final isSelected = _selectedIds.contains(teacherId);
    final isSelf = widget.controller.currentUser?['id'] == teacherId;

    final name = teacher['name']?.toString() ?? 'Guru';
    final rawNip = teacher['nip']?.toString().trim();
    final nip = (rawNip != null && rawNip.isNotEmpty && rawNip != '-') ? rawNip : '-';
    final rawEmail = teacher['email']?.toString().trim();
    final hasEmail = rawEmail != null && rawEmail.isNotEmpty && rawEmail != '-';
    final email = hasEmail ? rawEmail : null;
    final subRole = teacher['sub_role']?.toString() ?? 'guru';
    final classMajor = teacher['class_major']?['name']?.toString();

    String subRoleLabel;
    Color subRoleColor;
    switch (subRole.toLowerCase()) {
      case 'kepala_sekolah':
        subRoleLabel = 'Kepala Sekolah';
        subRoleColor = const Color(0xFF6366F1);
        break;
      case 'wakil_kepala_sekolah':
        subRoleLabel = 'Wakil Kepala';
        subRoleColor = const Color(0xFF3B82F6);
        break;
      case 'karyawan':
        subRoleLabel = 'Karyawan / TU';
        subRoleColor = const Color(0xFFF59E0B);
        break;
      default:
        subRoleLabel = 'Guru Pengajar';
        subRoleColor = const Color(0xFF10B981);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08)
            : (isDark ? AppTheme.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_isSelectionMode) {
              if (!isSelf) _toggleSelection(teacherId);
              return;
            }
            _showTeacherDetailModal(context, teacher);
          },
          onLongPress: () {
            if (isSelf) return;
            if (!_isSelectionMode) {
              _enterSelectionMode(teacherId);
            } else {
              _toggleSelection(teacherId);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _isSelectionMode
                      ? Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: isSelf
                              ? Tooltip(
                                  message: 'Akun Anda sendiri',
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.shield_outlined, color: Color(0xFF94A3B8), size: 20),
                                  ),
                                )
                              : ShieiCheckbox(
                                  value: isSelected,
                                  activeColor: const Color(0xFF10B981),
                                  onChanged: (_) => _toggleSelection(teacherId),
                                ),
                        )
                      : const SizedBox.shrink(),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: subRoleColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'G',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: subRoleColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: subRoleColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              subRoleLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: subRoleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'NIP: $nip',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                          if (classMajor != null && classMajor.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.16 : 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.22),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.meeting_room_outlined, size: 11.5, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Wali Kelas $classMajor',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (hasEmail) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 11.5,
                              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                email!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.controller.isAdmin)
                  PopupMenuButton<String>(
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 6),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                    tooltip: 'Aksi Guru',
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    surfaceTintColor: Colors.transparent,
                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                    onSelected: (val) {
                      if (val == 'detail') {
                        _showTeacherDetailModal(context, teacher);
                      } else if (val == 'edit') {
                        UserFormDialog.show(
                          context: context,
                          userData: teacher,
                          initialRole: 'teacher',
                          controller: widget.controller,
                        );
                      } else if (val == 'delete') {
                        ConfirmDeleteDialog.show(
                          context: context,
                          title: 'Hapus Akun Guru?',
                          itemName: name,
                          message: 'Akun guru ini dan riwayat penugasan akan dihapus secara permanen.',
                          onConfirm: () => widget.controller.deleteUser(teacher['id']),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'detail',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF10B981)),
                            SizedBox(width: 10),
                            Text('Detail Lengkap', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                            SizedBox(width: 10),
                            Text('Edit Guru', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      if (widget.controller.currentUser?['id'] != teacher['id'])
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                              SizedBox(width: 10),
                              Text('Hapus Guru', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFEF4444))),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFCBD5E1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- VIEW: SEMUA USER ---
  Widget _buildUsersView(bool isDark) {
    final users = widget.controller.filteredUsers;
    final isSearch = widget.controller.dataSearchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      color: const Color(0xFF3B82F6),
      onRefresh: () => widget.controller.loadAllUsers(clearPrevious: true),
      child: (widget.controller.isLoading || widget.controller.isUsersLoading)
          ? const ParticipantRowSkeleton(
              count: 6,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
              physics: AlwaysScrollableScrollPhysics(),
            )
          : users.isEmpty
              ? (isSearch
                  ? ShieiEmptyState.searchNotFound(
                      context: context,
                      searchQuery: widget.controller.dataSearchQuery,
                      categoryLabel: 'Pengguna',
                      accentColor: const Color(0xFF3B82F6),
                      isDark: isDark,
                      onClearSearch: () {
                        _searchController.clear();
                        widget.controller.setDataSearchQuery('');
                        setState(() {});
                      },
                    )
                  : ShieiEmptyState(
                      title: 'Belum Ada Pengguna Lain',
                      message: 'Database seluruh pengguna masih kosong di luar akun Anda.',
                      icon: Icons.group_outlined,
                      accentColor: const Color(0xFF3B82F6),
                      isDark: isDark,
                      primaryActionLabel: '+ Tambah Pengguna Baru',
                      onPrimaryAction: () => UserFormDialog.show(
                        context: context,
                        allowRoleChange: true,
                        controller: widget.controller,
                      ),
                    ))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: users.length,
                  itemBuilder: (ctx, index) {
                    final user = users[index];
                    return _buildUserItemCard(ctx, user, isDark);
                  },
                ),
    );
  }

  Widget _buildUserItemCard(BuildContext context, Map<String, dynamic> user, bool isDark) {
    final userId = user['id'] is int ? user['id'] as int : int.tryParse(user['id'].toString()) ?? 0;
    final isSelected = _selectedIds.contains(userId);
    final isSelf = widget.controller.currentUser?['id'] == userId;

    final name = user['name']?.toString() ?? 'Pengguna';
    final role = user['role']?.toString().toLowerCase() ?? 'student';
    final rawEmail = user['email']?.toString().trim();
    final hasEmail = rawEmail != null && rawEmail.isNotEmpty && rawEmail != '-';
    final email = hasEmail ? rawEmail : null;

    final rawNip = user['nip']?.toString().trim();
    final hasNip = rawNip != null && rawNip.isNotEmpty && rawNip != '-';
    final nip = hasNip ? rawNip : '-';

    final rawNisn = user['nisn']?.toString().trim();
    final hasNisn = rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-';
    final nisn = hasNisn ? rawNisn : '-';

    final rawClass = (user['class_major']?['name'] ?? user['classes']?['name'])?.toString().trim();
    final hasClass = rawClass != null && rawClass.isNotEmpty && rawClass != '-';
    final className = hasClass ? rawClass : null;

    String roleLabel;
    Color roleColor;
    IconData roleIcon;
    switch (role) {
      case 'school_admin':
        roleLabel = 'Admin';
        roleColor = const Color(0xFFF59E0B);
        roleIcon = Icons.admin_panel_settings_rounded;
        break;
      case 'teacher':
        roleLabel = 'Guru';
        roleColor = const Color(0xFF10B981);
        roleIcon = Icons.badge_rounded;
        break;
      default:
        roleLabel = 'Siswa';
        roleColor = const Color(0xFF8B5CF6);
        roleIcon = Icons.school_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.15 : 0.08)
            : (isDark ? AppTheme.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_isSelectionMode) {
              if (!isSelf) _toggleSelection(userId);
              return;
            }
            _showUserDetailModal(context, user);
          },
          onLongPress: () {
            if (isSelf) return;
            if (!_isSelectionMode) {
              _enterSelectionMode(userId);
            } else {
              _toggleSelection(userId);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _isSelectionMode
                      ? Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: isSelf
                              ? Tooltip(
                                  message: 'Akun Anda sendiri',
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.shield_outlined, color: Color(0xFF94A3B8), size: 20),
                                  ),
                                )
                              : ShieiCheckbox(
                                  value: isSelected,
                                  activeColor: const Color(0xFF3B82F6),
                                  onChanged: (_) => _toggleSelection(userId),
                                ),
                        )
                      : const SizedBox.shrink(),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Icon(roleIcon, color: roleColor, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (role == 'student') ...[
                        // Line 1: Kelas
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.16 : 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.35 : 0.22),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.school_outlined, size: 11.5, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 4),
                              Text(
                                hasClass ? 'Kelas $className' : 'Belum Ada Kelas',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Line 2: NISN
                        Text(
                          'NISN: $nisn',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ] else if (role == 'teacher') ...[
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'NIP: $nip',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                            if (hasClass)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.16 : 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.22),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.meeting_room_outlined, size: 11.5, color: Color(0xFF10B981)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Wali Kelas $className',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (hasEmail) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 11.5,
                                color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  email!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ] else ...[
                        // school_admin
                        Text(
                          'NIP: $nip',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                        if (hasEmail) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 11.5,
                                color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  email!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.controller.isAdmin)
                  PopupMenuButton<String>(
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 6),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                    tooltip: 'Aksi Pengguna',
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    surfaceTintColor: Colors.transparent,
                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                    onSelected: (val) {
                      if (val == 'detail') {
                        _showUserDetailModal(context, user);
                      } else if (val == 'mutasi') {
                        _showMutasiKelasDialog(context, user, isDark);
                      } else if (val == 'edit') {
                        UserFormDialog.show(
                          context: context,
                          userData: user,
                          initialRole: role,
                          controller: widget.controller,
                        );
                      } else if (val == 'delete') {
                        ConfirmDeleteDialog.show(
                          context: context,
                          title: 'Hapus Pengguna?',
                          itemName: name,
                          message: 'Akun "$name" ($roleLabel) akan dihapus secara permanen dari basis data sekolah.',
                          onConfirm: () => widget.controller.deleteUser(user['id']),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'detail',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF3B82F6)),
                            SizedBox(width: 10),
                            Text('Detail Pengguna', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      if (role == 'student')
                        const PopupMenuItem(
                          value: 'mutasi',
                          child: Row(
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFFF59E0B)),
                              SizedBox(width: 10),
                              Text('Mutasi Kelas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: Color(0xFF10B981)),
                            SizedBox(width: 10),
                            Text('Edit Pengguna', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      if (widget.controller.currentUser?['id'] != user['id'])
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                              SizedBox(width: 10),
                              Text('Hapus Pengguna', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFEF4444))),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFCBD5E1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- VIEW: KELAS ---
  Widget _buildClassesView(bool isDark) {
    final rawClasses = widget.controller.classes;
    final searchQuery = widget.controller.dataSearchQuery.toLowerCase();
    final classes = rawClasses.where((c) {
      if (searchQuery.isEmpty) return true;
      final name = (c['name'] ?? '').toString().toLowerCase();
      final level = (c['level'] ?? '').toString().toLowerCase();
      return name.contains(searchQuery) || level.contains(searchQuery);
    }).toList();

    final isSearch = searchQuery.isNotEmpty;

    return RefreshIndicator(
      color: const Color(0xFFF59E0B),
      onRefresh: () => widget.controller.loadClasses(clearPrevious: true),
      child: (widget.controller.isLoading || widget.controller.isClassesLoading)
          ? const ParticipantRowSkeleton(
              count: 6,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
              physics: AlwaysScrollableScrollPhysics(),
            )
          : classes.isEmpty
              ? (isSearch
                  ? ShieiEmptyState.searchNotFound(
                      context: context,
                      searchQuery: widget.controller.dataSearchQuery,
                      categoryLabel: 'Kelas',
                      accentColor: const Color(0xFFF59E0B),
                      isDark: isDark,
                      onClearSearch: () {
                        _searchController.clear();
                        widget.controller.setDataSearchQuery('');
                        setState(() {});
                      },
                    )
                  : ShieiEmptyState(
                      title: 'Belum Ada Kelas Terdaftar',
                      message: 'Daftar kelas sekolah masih kosong. Buat kelas baru untuk menampung data siswa.',
                      icon: Icons.meeting_room_outlined,
                      accentColor: const Color(0xFFF59E0B),
                      isDark: isDark,
                      primaryActionLabel: '+ Tambah Kelas Baru',
                      onPrimaryAction: () => ClassFormDialog.show(context: context, controller: widget.controller),
                    ))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: classes.length,
                  itemBuilder: (ctx, index) {
                final c = classes[index];
                final classId = c['id'];
                final name = c['name']?.toString() ?? 'Kelas';
                final classStudents = widget.controller.students.where((s) {
                  final sClassId = s['class_major_id'] ?? s['class_id'] ?? s['class_major']?['id'] ?? s['classes']?['id'];
                  return sClassId?.toString() == classId?.toString();
                }).toList();
                final rawStudentCount = c['student_count'] ?? c['students_count'] ?? c['users_count'];
                final studentsInClass = rawStudentCount != null
                    ? (int.tryParse(rawStudentCount.toString()) ?? classStudents.length)
                    : classStudents.length;
                final rawBoundCount = c['bound_devices_count'];
                final boundCount = rawBoundCount != null
                    ? (int.tryParse(rawBoundCount.toString()) ??
                        classStudents.where((s) {
                          final sn = s['serial_number']?.toString();
                          final dn = s['device_name']?.toString();
                          return (sn != null && sn.isNotEmpty) || (dn != null && dn.isNotEmpty);
                        }).length)
                    : classStudents.where((s) {
                        final sn = s['serial_number']?.toString();
                        final dn = s['device_name']?.toString();
                        return (sn != null && sn.isNotEmpty) || (dn != null && dn.isNotEmpty);
                      }).length;

                final level = ClassFormDialog.getLevel(name);
                final major = ClassFormDialog.extractMajor(name);

                final assignedTeachers = widget.controller.teachers.where((t) {
                  final tClassId = t['class_major_id'] ?? t['class_id'] ?? t['class_major']?['id'] ?? t['classes']?['id'];
                  return tClassId?.toString() == classId?.toString();
                }).toList();
                final waliTeacher = assignedTeachers.isNotEmpty ? assignedTeachers.first : null;
                final isMyClass = (widget.controller.isWaliKelas && widget.controller.waliKelasId?.toString() == classId?.toString()) ||
                    (waliTeacher != null && waliTeacher['id']?.toString() == widget.controller.currentUser?['id']?.toString());

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isMyClass
                          ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.6 : 0.45)
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      width: isMyClass ? 1.4 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isMyClass
                            ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.06)
                            : Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ClassDetailScreen(
                              classData: c,
                              controller: widget.controller,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. TOP HEADER: Icon, Title, Badges, and Action Popup
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: (isMyClass ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: (isMyClass ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.meeting_room_rounded,
                                      color: isMyClass ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: -0.2,
                                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isMyClass) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: const Text(
                                                'Kelas Anda',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              level != 'OTHER' ? 'Tingkat $level' : 'Umum',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                          if (major.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                major,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFD97706),
                                                ),
                                              ),
                                            ),
                                          Text(
                                            'ID #$classId',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.controller.isAdmin)
                                  PopupMenuButton<String>(
                                    position: PopupMenuPosition.under,
                                    offset: const Offset(0, 6),
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                    tooltip: 'Aksi Kelas',
                                    padding: EdgeInsets.zero,
                                    borderRadius: BorderRadius.circular(8),
                                    clipBehavior: Clip.antiAlias,
                                    surfaceTintColor: Colors.transparent,
                                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                    ),
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        ClassFormDialog.show(
                                          context: context,
                                          classData: c,
                                          controller: widget.controller,
                                        );
                                      } else if (val == 'delete') {
                                        final hasStudents = studentsInClass > 0;
                                        ConfirmDeleteDialog.show(
                                          context: context,
                                          title: hasStudents ? 'Hapus Kelas & Seluruh Siswa?' : 'Hapus Kelas?',
                                          itemType: 'Nama Kelas',
                                          itemName: name,
                                          message: hasStudents
                                              ? 'Kelas "$name" saat ini memiliki $studentsInClass siswa aktif terdaftar.'
                                              : 'Apakah Anda yakin ingin menghapus kelas "$name"? Tidak ada siswa yang terdaftar di kelas ini.',
                                          warningNote: hasStudents
                                              ? 'PERINGATAN PENTING: Menghapus kelas ini akan secara otomatis MENGHAPUS SEMUA $studentsInClass SISWA di dalamnya beserta seluruh akun login, ikatan perangkat HP, dan riwayat ujian mereka. Tindakan ini bersifat permanen!'
                                              : null,
                                          confirmLabel: hasStudents ? 'Hapus Kelas & $studentsInClass Siswa' : 'Hapus Kelas',
                                          onConfirm: () => widget.controller.deleteClass(classId),
                                        );
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                                            SizedBox(width: 10),
                                            Text('Edit Kelas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                            SizedBox(width: 10),
                                            Text('Hapus Kelas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFEF4444))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 2. METRICS STRIP: Total Siswa & Perangkat Terikat (2 Micro-Cards)
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.people_alt_outlined,
                                            size: 16,
                                            color: Color(0xFF6366F1),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'SISWA',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              ShieiAnimatedCounter(
                                                count: studentsInClass,
                                                suffix: ' Siswa',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: (boundCount > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            boundCount > 0 ? Icons.smartphone_rounded : Icons.phonelink_off_rounded,
                                            size: 16,
                                            color: boundCount > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'HP TERIKAT',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              boundCount > 0
                                                  ? ShieiAnimatedCounter(
                                                      count: boundCount,
                                                      suffix: ' Terikat',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF10B981),
                                                      ),
                                                    )
                                                  : Text(
                                                      'Belum Ada',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                                                      ),
                                                    ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // 3. WALI KELAS STRIP
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: (isMyClass
                                        ? const Color(0xFF10B981)
                                        : (waliTeacher != null ? const Color(0xFFF59E0B) : const Color(0xFF64748B)))
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (isMyClass
                                          ? const Color(0xFF10B981)
                                          : (waliTeacher != null ? const Color(0xFFF59E0B) : const Color(0xFF64748B)))
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: (isMyClass
                                              ? const Color(0xFF10B981)
                                              : (waliTeacher != null ? const Color(0xFFF59E0B) : const Color(0xFF64748B)))
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      waliTeacher != null && (waliTeacher['name']?.toString().isNotEmpty ?? false)
                                          ? (waliTeacher['name'] as String)[0].toUpperCase()
                                          : '—',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: isMyClass
                                            ? const Color(0xFF10B981)
                                            : (waliTeacher != null ? const Color(0xFFD97706) : const Color(0xFF64748B)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isMyClass ? 'Wali Kelas (Anda):' : 'Wali Kelas:',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                          ),
                                        ),
                                        Text(
                                          waliTeacher?['name']?.toString() ?? 'Belum Ditugaskan',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (waliTeacher != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (isMyClass ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        assignedTeachers.length > 1 ? '${assignedTeachers.length} Pengajar' : 'Wali Kelas',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isMyClass ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 4. BOTTOM BAR: Detail Link
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Detail Kelas',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SpeedDialItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _SpeedDialOverlayWidget extends StatelessWidget {
  final Animation<double> animation;
  final bool isDark;
  final Offset fabOffset;
  final Size fabSize;
  final String category;
  final List<_SpeedDialItem> items;
  final VoidCallback onClose;

  const _SpeedDialOverlayWidget({
    required this.animation,
    required this.isDark,
    required this.fabOffset,
    required this.fabSize,
    required this.category,
    required this.items,
    required this.onClose,
  });

  Color _getFabColor() {
    switch (category) {
      case 'teachers':
        return const Color(0xFF10B981);
      case 'classes':
        return const Color(0xFFF59E0B);
      case 'users':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double rightMargin = (screenSize.width - (fabOffset.dx + fabSize.width)).clamp(0.0, screenSize.width);
    final double bottomMargin = (screenSize.height - fabOffset.dy + 12).clamp(0.0, screenSize.height);
    final fabColor = _getFabColor();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 1. Full Screen Backdrop Overlay (Blur + Dim, covers 100% of the screen including Appbar & Navbar)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (ctx, _) {
                    final rawVal = animation.value.clamp(0.0, 1.0);
                    final blurProgress = Curves.easeOut.transform(rawVal);
                    return BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 3.5 * blurProgress,
                        sigmaY: 3.5 * blurProgress,
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.50 * blurProgress),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 2. Staggered Animated Flyout Items (Above the FAB)
            Positioned(
              right: rightMargin,
              bottom: bottomMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _buildAnimatedFlyoutItem(context, items[i], i, items.length),
                ],
              ),
            ),

            // 3. Elevated Active FAB (Rotates '+' into 'x', glows above backdrop)
            Positioned(
              left: fabOffset.dx,
              top: fabOffset.dy,
              width: fabSize.width,
              height: fabSize.height,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onClose();
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: fabColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: fabColor.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (ctx, child) {
                          final rawVal = animation.value.clamp(0.0, 1.0);
                          final rotateProgress = Curves.easeOutCubic.transform(rawVal);
                          return Transform.rotate(
                            angle: rotateProgress * (math.pi / 4),
                            child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedFlyoutItem(
    BuildContext context,
    _SpeedDialItem item,
    int index,
    int totalCount,
  ) {
    // Bottom-most item (closest to FAB) emerges first
    final int reverseIndex = (totalCount - 1) - index;
    // Calculate staggered time intervals strictly clamped across 400ms window
    final double start = (reverseIndex * 0.15).clamp(0.0, 0.40);
    final double end = (start + 0.60).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, child) {
        final double rawVal = animation.value.clamp(0.0, 1.0);
        double t = 0.0;
        if (rawVal > start) {
          t = ((rawVal - start) / (end - start)).clamp(0.0, 1.0);
        }
        final double curvedT = Curves.easeOutCubic.transform(t);

        // USER PREFERENCE: SLIDE IN FROM SIDE ONLY (RIGHT -> LEFT), NO BOTTOM SLIDE!
        final double slideX = (1.0 - curvedT) * 50.0;
        final double scale = 0.88 + (0.12 * curvedT);

        return Transform.translate(
          offset: Offset(slideX, 0.0), // Zero Y-offset: pure horizontal slide!
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: curvedT,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SpeedDialItemRow(
                  item: item,
                  isDark: isDark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedDialItemRow extends StatefulWidget {
  final _SpeedDialItem item;
  final bool isDark;

  const _SpeedDialItemRow({
    required this.item,
    required this.isDark,
  });

  @override
  State<_SpeedDialItemRow> createState() => _SpeedDialItemRowState();
}

class _SpeedDialItemRowState extends State<_SpeedDialItemRow> {
  bool _isPressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text Label Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Circular Mini FAB
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.item.color.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.item.color.withValues(alpha: widget.isDark ? 0.3 : 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(widget.item.icon, size: 20, color: widget.item.color),
            ),
          ],
        ),
      ),
    );
  }
}


