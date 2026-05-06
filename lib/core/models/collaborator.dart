/// Collaborator — a user with a role on a shared notebook.
enum CollaboratorRole { owner, editor, viewer }

class Collaborator {
  final String uid;
  final String email;
  final CollaboratorRole role;

  const Collaborator({
    required this.uid,
    required this.email,
    required this.role,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'role': role.name,
      };

  factory Collaborator.fromMap(Map<String, dynamic> map) => Collaborator(
        uid: map['uid'] as String? ?? '',
        email: map['email'] as String? ?? '',
        role: CollaboratorRole.values.firstWhere(
          (r) => r.name == (map['role'] as String? ?? 'viewer'),
          orElse: () => CollaboratorRole.viewer,
        ),
      );
}
