/// NotePage — page index entry. Content lives in Drive JSON, referenced by driveFileId.
class NotePage {
  final String id;
  final String sectionId;
  final String notebookId;
  final String title;
  final String? driveFileId;
  final int order;
  final int indentLevel;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NotePage({
    required this.id,
    required this.sectionId,
    required this.notebookId,
    required this.title,
    this.driveFileId,
    required this.order,
    this.indentLevel = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  NotePage copyWith({
    String? title,
    String? driveFileId,
    int? order,
    int? indentLevel,
    DateTime? updatedAt,
  }) =>
      NotePage(
        id: id,
        sectionId: sectionId,
        notebookId: notebookId,
        title: title ?? this.title,
        driveFileId: driveFileId ?? this.driveFileId,
        order: order ?? this.order,
        indentLevel: indentLevel ?? this.indentLevel,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'sectionId': sectionId,
        'notebookId': notebookId,
        'title': title,
        'driveFileId': driveFileId,
        'order': order,
        'indentLevel': indentLevel,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory NotePage.fromMap(String id, Map<String, dynamic> map) => NotePage(
        id: id,
        sectionId: map['sectionId'] as String? ?? '',
        notebookId: map['notebookId'] as String? ?? '',
        title: map['title'] as String? ?? 'Untitled page',
        driveFileId: map['driveFileId'] as String?,
        order: map['order'] as int? ?? 0,
        indentLevel: map['indentLevel'] as int? ?? 0,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
