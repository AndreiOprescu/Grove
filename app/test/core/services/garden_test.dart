// Port of Tests/GroveCoreTests/GardenTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/services/garden.dart';

import '../../data/helpers.dart';

void main() {
  final last = Garden.stages.length - 1;

  test('there are many stages from a seed to a tree', () {
    expect(Garden.stages.length, 12);
    expect(Garden.stages.first.name, 'Seed');
    expect(Garden.stages.last.name, 'Ancient tree');
  });

  test('stages start at zero and need more tasks each time', () {
    expect(Garden.stages.first.from, 0);
    for (var i = 0; i < last; i++) {
      expect(Garden.stages[i].from, lessThan(Garden.stages[i + 1].from));
    }
    expect(Garden.stages.map((s) => s.name).toSet().length, 12);
    for (final (i, s) in Garden.stages.indexed) {
      expect(s.index, i);
    }
  });

  test('the stage comes from the number of finished tasks', () {
    String name(int done) => Garden.stage(done: done).name;
    expect(name(0), 'Seed');
    expect(name(1), 'Sprout');
    expect(name(2), 'Sprout');
    expect(name(3), 'Seedling');
    expect(name(119), 'Full tree');
    expect(name(120), 'Ancient tree');
    expect(name(5000), 'Ancient tree');
    expect(name(-4), 'Seed');
  });

  test('every finished task makes the plant grow a unit', () {
    // A real, gradual change: no task leaves the plant as it was, until the
    // last stage.
    final top = Garden.stages[last].from;
    for (var done = 0; done < top; done++) {
      expect(
        Garden.growth(done: done + 1),
        greaterThan(Garden.growth(done: done)),
        reason: 'task ${done + 1}',
      );
    }
  });

  test('growth is the stage number at the start of a stage', () {
    for (final s in Garden.stages) {
      expect(Garden.growth(done: s.from), s.index.toDouble());
    }
  });

  test('growth stays between the stages and stops at the top', () {
    final mid = Garden.growth(done: 4);
    expect(mid > 2 && mid < 3, isTrue);
    expect(Garden.growth(done: 100000), last.toDouble());
    expect(Garden.growth(done: -1), 0);
    expect(Garden.maxGrowth, last.toDouble());
  });

  test('the progress in a stage goes from zero to just under one', () {
    expect(Garden.progress(done: 3), 0);
    final p = Garden.progress(done: 4);
    expect(p > 0 && p < 1, isTrue);
    expect(Garden.progress(done: 5), greaterThan(p));
    expect(Garden.progress(done: 120), 1);
    expect(Garden.progress(done: 9999), 1);
  });

  test('the next stage and the tasks still needed', () {
    expect(Garden.next(after: 0)?.name, 'Sprout');
    expect(Garden.tasksToNext(done: 0), 1);
    expect(Garden.tasksToNext(done: 1), 2);
    expect(Garden.tasksToNext(done: 2), 1);
    expect(Garden.next(after: 120), isNull);
    expect(Garden.tasksToNext(done: 120), isNull);
  });

  test('the done count is the finished tasks in the database', () {
    final r = makeRepos();
    expect(r.tasks.doneCount(), 0);
    r.tasks.save(TaskItem(id: 'A', title: 'a', status: TaskStatus.done));
    r.tasks.save(TaskItem(id: 'B', title: 'b', status: TaskStatus.cancelled));
    r.tasks.save(TaskItem(id: 'C', title: 'c'));
    expect(r.tasks.doneCount(), 1);
  });
}
