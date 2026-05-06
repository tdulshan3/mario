/// Section — tab inside a notebook, holds an ordered list of pages.
class Section {
  final String id;
  final String notebookId;
  final String name;
  final int colorIndex;
  final int order;

  const Section({
    required this.id,
    required this.notebookId,
    required this.name,
    this.colorIndex = 2,
    required this.order,
  });

  Section copyWith({String? name, int? colorIndex, int? order}) => Section(
        id: id,
        notebookId: notebookId,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        order: order ?? this.order,
      );

  Map<String, dynamic> toMap() => {
        'notebookId': notebookId,
        'name': name,
        'colorIndex': colorIndex,
        'order': order,
      };

  factory Section.fromMap(String id, Map<String, dynamic> map) => Section(
        id: id,
        notebookId: map['notebookId'] as String? ?? '',
        name: map['name'] as String? ?? 'Untitled',
        colorIndex: map['colorIndex'] as int? ?? 2,
        order: map['order'] as int? ?? 0,
      );
}
