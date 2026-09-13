/// Defines the build flavor and target audience for the app.
enum AppFlavor {
  /// All-in-one unified app with role-based routing (Default/Dev)
  unified,

  /// Resident app: Flat-based authentication, dues payment, visitor approvals, alerts, helpdesk
  resident,

  /// Guard gate kiosk: Fast staff/PIN sign-in, walk-in camera, parcel check-in, pass verification
  guard,

  /// Admin management portal: Committee accounting, maintenance billing, society config, notices
  admin,
}

/// Global configuration container for the currently active app flavor.
class AppFlavorConfig {
  final AppFlavor flavor;
  final String appTitle;
  final String appSubtitle;
  final String defaultRole;
  final List<String> allowedRoles;

  const AppFlavorConfig({
    required this.flavor,
    required this.appTitle,
    required this.appSubtitle,
    required this.defaultRole,
    required this.allowedRoles,
  });

  static late AppFlavorConfig _current;

  static AppFlavorConfig get current => _current;

  static bool get isInitialized => _isInitialized;
  static bool _isInitialized = false;

  static void initialize(AppFlavor flavor) {
    switch (flavor) {
      case AppFlavor.resident:
        _current = const AppFlavorConfig(
          flavor: AppFlavor.resident,
          appTitle: 'Ramkrishnapuram Resident',
          appSubtitle: 'Resident Portal & Community Services',
          defaultRole: 'RESIDENT',
          allowedRoles: ['RESIDENT'],
        );
        break;
      case AppFlavor.guard:
        _current = const AppFlavorConfig(
          flavor: AppFlavor.guard,
          appTitle: 'Gate Security Kiosk',
          appSubtitle: 'Main Gate & Perimeter Management',
          defaultRole: 'GUARD',
          allowedRoles: ['GUARD'],
        );
        break;
      case AppFlavor.admin:
        _current = const AppFlavorConfig(
          flavor: AppFlavor.admin,
          appTitle: 'Ramkrishnapuram RWA Admin',
          appSubtitle: 'Society Governance & Accounting Portal',
          defaultRole: 'ADMIN',
          allowedRoles: ['ADMIN'],
        );
        break;
      case AppFlavor.unified:
        _current = const AppFlavorConfig(
          flavor: AppFlavor.unified,
          appTitle: 'Ramkrishnapuram RWA',
          appSubtitle: 'Smart Society Management Suite',
          defaultRole: 'RESIDENT',
          allowedRoles: ['RESIDENT', 'GUARD', 'ADMIN'],
        );
        break;
    }
    _isInitialized = true;
  }

  bool isRoleAllowed(String? role) {
    if (flavor == AppFlavor.unified) return true;
    if (role == null) return false;
    return allowedRoles.contains(role.toUpperCase());
  }
}
