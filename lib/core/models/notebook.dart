/// Notebook — top-level container for sections and pages.
import 'package:flutter/material.dart';

import '../../ui/colors.dart';

class Notebook {
  final String id;
  final String name;
  final String ownerId;
  final List<String> collaboratorUids;
  final int colorIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Notebook({
    required this.id,
    required this.name,
    required this.ownerId,
    this.collaboratorUids = const [],
    this.colorIndex = 2,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get color => MarioColors.labelPalette[
      colorIndex.clamp(0, MarioColors.labelPalette.length - 1)];

  Notebook copyWith({
    String? name,
    int? colorIndex,
    List<String>? collaboratorUids,
    DateTime? updatedAt,
  }) =>
      Notebook(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        collaboratorUids: collaboratorUids ?? this.collaboratorUids,
        colorIndex: colorIndex ?? this.colorIndex,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerId': ownerId,
        'collaboratorUids': collaboratorUids,
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Notebook.fromMap(String id, Map<String, dynamic> map) => Notebook(
        id: id,
        name: map['name'] as String? ?? 'Untitled',
        ownerId: map['ownerId'] as String? ?? '',
        collaboratorUids:
            List<String>.from(map['collaboratorUids'] as List? ?? const []),
        colorIndex: map['colorIndex'] as int? ?? 2,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
