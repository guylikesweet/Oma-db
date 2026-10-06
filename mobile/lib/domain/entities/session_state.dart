class SessionState {
  const SessionState({
    this.userId,
    this.username = '',
    this.role = 'staff',
    this.isPrimaryAdmin = false,
    this.authenticated = false,
  });

  final int? userId;
  final String username;
  final String role;
  final bool isPrimaryAdmin;
  final bool authenticated;

  bool get isAdmin => role == 'admin';

  const SessionState.signedOut() : this();

  SessionState copyWith({
    int? userId,
    String? username,
    String? role,
    bool? isPrimaryAdmin,
    bool? authenticated,
  }) {
    return SessionState(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      role: role ?? this.role,
      isPrimaryAdmin: isPrimaryAdmin ?? this.isPrimaryAdmin,
      authenticated: authenticated ?? this.authenticated,
    );
  }
}
