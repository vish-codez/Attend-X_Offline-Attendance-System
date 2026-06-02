class UserModel {
  final String token;
  final String username;
  final String role;
  final int userId;
  final String fullName;

  // Student fields
  final String? rollNumber;
  final String? departmentName;
  final int? yearOfStudy;
  final String? section;

  // Teacher fields
  final String? employeeId;
  final String? teacherDepartmentName;

  const UserModel({
    required this.token,
    required this.username,
    required this.role,
    required this.userId,
    required this.fullName,
    this.rollNumber,
    this.departmentName,
    this.yearOfStudy,
    this.section,
    this.employeeId,
    this.teacherDepartmentName,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      token: json['token'] ?? '',
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      userId: json['userId'] ?? 0,
      fullName: json['fullName'] ?? '',
      rollNumber: json['rollNumber'],
      departmentName: json['departmentName'],
      yearOfStudy: json['yearOfStudy'],
      section: json['section'],
      employeeId: json['employeeId'],
      teacherDepartmentName: json['teacherDepartmentName'],
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'username': username,
    'role': role,
    'userId': userId,
    'fullName': fullName,
    'rollNumber': rollNumber,
    'departmentName': departmentName,
    'yearOfStudy': yearOfStudy,
    'section': section,
    'employeeId': employeeId,
    'teacherDepartmentName': teacherDepartmentName,
  };
}