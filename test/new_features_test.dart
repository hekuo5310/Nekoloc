import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/composer_tools.dart';
import 'package:nodeloc_app/models.dart';
import 'package:nodeloc_app/search_query.dart';
import 'package:nodeloc_app/widgets/poll_card.dart';

void main() {
  test('format selected text and reversed selections without losing surrounding text', () {
    final value = wrapSelection(const TextEditingValue(text: 'hello world!',
      selection: TextSelection(baseOffset: 11, extentOffset: 6)), '**', '**');
    expect(value.text, 'hello **world**!');
    expect(value.selection.textInside(value.text), 'world');
    final empty = wrapSelection(const TextEditingValue(text: '正文'), '[', '](https://)', placeholder: '链接');
    expect(empty.text, '正文[链接](https://)');
    expect(empty.selection.textInside(empty.text), '链接');
  });

  test('line tools start at the line boundary and prefix each selected line', () {
    final result = prefixLines(const TextEditingValue(text: 'first\nsecond\nthird',
      selection: TextSelection(baseOffset: 8, extentOffset: 18)), '> ');
    expect(result.text, 'first\n> second\n> third');
    expect(result.selection.baseOffset, result.text.length);
  });

  test('poll builder creates unique named blocks and validates user input', () {
    final poll = buildPollMarkup('[poll name=poll1]\n[/poll]', [' A ', 'B'], multiple: true);
    expect(poll, contains('name=poll2 type=multiple min=1 max=2'));
    expect(poll, contains('* A\n* B'));
    expect(() => buildPollMarkup('', ['A']), throwsFormatException);
    expect(() => buildPollMarkup('', ['A', 'A']), throwsFormatException);
    expect(() => buildPollMarkup('', ['A', '[/poll]']), throwsFormatException);
  });

  test('polls preserve hidden counts, named votes and copy with other interactions', () {
    final post = Post.fromJson({'id': 10, 'post_number': 2,
      'polls': [{'name': 'choices', 'type': 'multiple', 'min': 2, 'max': 3,
        'options': [{'id': 'a', 'html': 'A'}, {'id': 'b', 'html': 'B', 'votes': 0}, {'id': 'c', 'html': 'C'}]}],
      'polls_votes': {'choices': ['a', 'b']}});
    expect(post.polls.single.options.first.votes, isNull);
    expect(post.polls.single.options[1].votes, 0);
    expect(post.polls.single.validSelection({'a'}), isFalse);
    expect(post.polls.single.validSelection({'a', 'b'}), isTrue);
    expect(post.polls.single.validSelection({'a', 'missing'}), isFalse);
    expect(post.copyWith(bookmarked: true).pollsVotes['choices'], ['a', 'b']);
    expect(PostPoll.fromJson({'type': 'number'}).canVote, isFalse);
    expect(PostPoll.fromJson({'status': 'closed'}).canVote, isFalse);
    expect(PostPoll.fromJson({}).name, 'poll');
  });

  test('reaction updates preserve concurrent poll and bookmark changes', () {
    final post = Post.fromJson({'id': 10, 'bookmarked': true, 'bookmark_id': 22,
      'vote_score': 5, 'current_user_reaction': 'heart',
      'polls_votes': {'poll': ['a']}, 'like_count': 2});
    final update = post.mergeReactionUpdate({'id': 10,
      'current_user_reaction': null, 'reaction_users_count': 3,
      'bookmarked': false, 'polls_votes': {}, 'vote_score': 4});
    expect(update.currentUserReaction, isNull);
    expect(update.bookmarkId, 22);
    expect(update.bookmarked, isTrue);
    expect(update.pollsVotes['poll'], ['a']);
    expect(update.voteScore, 5);
    expect(update.likeCount, 2);
    expect(update.reactionUsersCount, 3);
  });

  test('search preserves post identity and server pagination signal', () {
    final result = SearchResult.fromJson({'topics': [{'id': 1, 'title': 'Topic'}],
      'posts': [{'id': 88, 'topic_id': 1, 'post_number': 9}],
      'grouped_search_result': {'more_full_page_results': true}});
    expect(result.items.single.id, 88);
    expect(result.items.single.postNumber, 9);
    expect(result.hasMore, isTrue);
    expect(SearchResult.fromJson({}).hasMore, isFalse);
    expect(buildSearchQuery('hello', titleOnly: true, username: 'alice', tag: 'flutter', order: 'latest'),
      'hello in:title @alice tags:flutter order:latest');
  });

  test('a reply cannot remove a topic-wide bookmark and deleted ids are cleared', () {
    final bookmarks = [BookmarkItem(id: 1, topicId: 3, title: '', excerpt: '')];
    expect(bookmarkIdForPost(bookmarks, 4, 3, allowTopicBookmark: false), isNull);
    expect(bookmarkIdForPost(bookmarks, 4, 3), 1);
    final post = Post.fromJson({'id': 4, 'bookmark_id': 1, 'bookmarked': true});
    expect(post.copyWith(bookmarked: false, clearBookmarkId: true).bookmarkId, isNull);
  });

  testWidgets('multiple-choice poll stages selections and enforces minimum', (tester) async {
    final poll = PostPoll.fromJson({'type': 'multiple', 'min': 2, 'max': 2,
      'options': [{'id': 'a', 'html': 'A'}, {'id': 'b', 'html': 'B'}, {'id': 'c', 'html': 'C'}]});
    List<String>? submitted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PollCard(poll: poll,
      myVotes: const [], busy: false, loggedIn: true,
      onVote: (v) => submitted = v, onRemove: () {}))));
    expect(find.text('0 票'), findsNothing);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '提交投票')).onPressed, isNull);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '提交投票'));
    expect(submitted, ['a', 'b']);
  });

  testWidgets('closed and logged-out polls cannot submit votes', (tester) async {
    var count = 0;
    for (final closed in [true, false]) {
      final poll = PostPoll.fromJson({'status': closed ? 'closed' : 'open',
        'options': [{'id': 'a', 'html': 'A'}]});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PollCard(poll: poll,
        myVotes: const [], busy: false, loggedIn: false,
        onVote: (_) => count++, onRemove: () => count++))));
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pump();
    }
    expect(count, 0);
  });
}
