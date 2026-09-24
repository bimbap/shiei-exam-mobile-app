class ApiEndpoints {
  // Auth
  static const String login = '/auth/login';
  static const String studentLogin = '/auth/student-login';
  static const String adminLogin = '/auth/admin-login';
  static const String logout = '/auth/logout';
  static const String me = '/user/me';
  static const String userProfile = '/user/profile';
  static const String updatePassword = '/user/password';
  static const String verifyPassword = '/user/verify-password';
  static const String verifyDevice = '/user/verify-device';

  // Student Operations
  static const String studentExams = '/student/exams';
  static String studentExamDetail(int linkId) => '/student/exams/$linkId';
  static const String recordProgress = '/student/progress';
  static const String phoneCallStatus = '/student/phone-call';
  static const String chargingStatus = '/student/charging-status';
  static const String cheatEvent = '/student/cheat-event';
  static String progressByExam(int linkId) => '/student/progress/exams/$linkId';
  static String examAnnouncements(int linkId) => '/student/exams/$linkId/announcements';
  static const String studentHistory = '/student/history';

  // Teacher / School Admin Operations
  static const String schoolProfile = '/school/profile';
  static const String schoolMonitoring = '/school/monitoring';
  static const String schoolCheatingLogs = '/school/cheating-logs';
  static const String schoolExams = '/school/exams';
  static const String schoolClasses = '/school/classes';
  static const String schoolStudents = '/school/students';
  static const String schoolStudentsBulk = '/school/students/bulk';
  static const String schoolStudentsBulkDelete = '/school/students/bulk-delete';
  static const String schoolTeachers = '/school/teachers';
  static const String schoolTeachersBulk = '/school/teachers/bulk';
  static const String schoolTeachersBulkDelete = '/school/teachers/bulk-delete';
  static const String schoolUsers = '/school/users';
  static const String schoolUsersBulk = '/school/users/bulk';
  static const String schoolUsersBulkDelete = '/school/users/bulk-delete';
  static String schoolExamDetail(int id) => '/school/exams/$id';
  static String rotateExamToken(int id) => '/school/exams/$id/rotate-token';
  static String unlockExam(int linkId, int studentId) => '/school/exams/$linkId/students/$studentId/unlock';
  static String addExtraTime(int linkId, int studentId) => '/school/exams/$linkId/students/$studentId/add-time';
  static String kickStudent(int linkId, int studentId) => '/school/exams/$linkId/students/$studentId/kick';
  static String schoolClassDetail(int id) => '/school/classes/$id';
  static String schoolUserDetail(int id) => '/school/users/$id';
  static String schoolTeacherDetail(int id) => '/school/teachers/$id';
  static String updateStudent(int id) => '/school/students/$id';
  static String transferStudentClass(int id) => '/school/students/$id/transfer-class';
  static String schoolExamAnnouncements(int id) => '/school/exams/$id/announcements';
  static String schoolDeleteAnnouncement(int examId, int announcementId) => '/school/exams/$examId/announcements/$announcementId';
  static String examProctors(dynamic id) => '/school/exams/$id/proctors';
  static String removeExamProctor(dynamic id, dynamic teacherId) => '/school/exams/$id/proctors/$teacherId';
}
