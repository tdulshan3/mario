/// The agent is handed a description of Mario and a set of skills, not a
/// list of rules — and a user can add skills of their own.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/mario_skills.dart';

void main() {
  group('the prompt', () {
    test('opens with the role and carries every bundled skill', () {
      final prompt = marioAgentPrompt();
      expect(prompt, startsWith("You are Mario's agent."));
      for (final skill in marioBundledSkills) {
        expect(prompt, contains(skill.trim()));
      }
    });

    test('names every action the plan schema accepts', () {
      final prompt = marioAgentPrompt();
      for (final action in [
        'replace_block',
        'delete_block',
        'move_block',
        '`markdown`',
        'rename_page',
        'create_page',
        'create_section',
        'create_notebook',
        'rename_section',
        'write_page',
        'open_page',
        'read_page',
        'list_notebooks',
        'list_pages',
        'search_notes',
        'web_search',
        'ask_user',
        'followUps',
        'setting',
      ]) {
        expect(prompt, contains(action), reason: action);
      }
    });

    test('tells the model what Mario renders', () {
      final prompt = marioAgentPrompt();
      expect(prompt, contains('[!NOTE]'));
      expect(prompt, contains(':emoji:'));
      expect(prompt, contains('```math'));
    });

    test('is not a rulebook', () {
      final prompt = marioAgentPrompt().toLowerCase();
      expect(prompt, isNot(contains('nothing else')));
      expect(prompt, isNot(contains('never write a level-1')));
    });

    test('appends the skills a user added, under their own heading', () {
      final prompt = marioAgentPrompt(
          userSkills: ['# Lab notebook\nAlways date entries.']);
      expect(prompt, contains('# Skills the user added'));
      expect(prompt, endsWith('Always date entries.'));
      expect(marioAgentPrompt(), isNot(contains('Skills the user added')));
    });
  });

  group('user skills on disk', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mario-skills-');
    });
    tearDown(() => dir.delete(recursive: true));

    test('every .md file, in name order, trimmed', () async {
      await File('${dir.path}/b-second.md').writeAsString('second\n');
      await File('${dir.path}/a-first.md').writeAsString('\nfirst');
      await File('${dir.path}/ignored.txt').writeAsString('nope');
      await File('${dir.path}/empty.md').writeAsString('  ');
      expect(await loadUserSkills(directory: dir), ['first', 'second']);
    });

    test('a missing folder is no skills, not an error', () async {
      final missing = Directory('${dir.path}/nope');
      expect(await loadUserSkills(directory: missing), isEmpty);
    });

    test('a huge file is clipped rather than crowding out the page', () async {
      await File('${dir.path}/big.md').writeAsString('x' * 20000);
      final skills = await loadUserSkills(directory: dir);
      expect(skills.single.length, lessThan(10000));
    });
  });
}
