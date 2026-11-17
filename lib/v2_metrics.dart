import 'dart:convert';
import 'package:html/dom.dart';

int v2Thanks(Element root, {bool original = false}) {
  if (original) {
    for (final script
        in root.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final data = jsonDecode(script.text);
        if (data is! Map || data['@type'] != 'DiscussionForumPosting') continue;
        final stats = data['interactionStatistic'];
        for (final stat in stats is List ? stats : [stats]) {
          if (stat is Map &&
              stat['interactionType'] == 'https://schema.org/LikeAction') {
            return int.tryParse('${stat['userInteractionCount']}') ?? 0;
          }
        }
      } catch (_) {}
    }
    return 0;
  }
  final heart = root.querySelector(
      'span.small.fade img[src*="heart"], span.small.fade img[alt="❤️"]');
  return int.tryParse(heart?.parent?.text.trim().replaceAll(',', '') ?? '') ??
      0;
}

int v2Votes(Element root, int topicId) {
  final vote =
      root.querySelector('#topic_${topicId}_votes a[onclick*="upVoteTopic"]');
  return int.tryParse(vote?.text.trim().replaceAll(',', '') ?? '') ?? 0;
}
