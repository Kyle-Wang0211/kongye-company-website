import 'dart:async';

import 'package:flutter/material.dart';

import '../../community/community_search_service.dart';
import '../../community/feed_models.dart';
import '../../l10n/app_localizations.dart';

class CommunitySearchPage extends StatefulWidget {
  const CommunitySearchPage({
    super.key,
    this.service,
    required this.onWorkSelected,
  });

  final CommunitySearchService? service;
  final ValueChanged<FeedWork> onWorkSelected;

  @override
  State<CommunitySearchPage> createState() => _CommunitySearchPageState();
}

class _CommunitySearchPageState extends State<CommunitySearchPage> {
  late final _service = widget.service ?? CommunitySearchService();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  bool _failed = false;
  bool _submitted = false;
  List<String> _suggestions = const [];
  List<FeedWork> _works = const [];

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _submitted = false;
      _failed = false;
      _works = const [];
      _suggestions = const [];
      _loading = value.trim().isNotEmpty;
    });
    if (value.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final suggestions = await _service.suggest(value);
        if (!mounted || generation != _generation) return;
        setState(() {
          _suggestions = suggestions;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  Future<void> _search([String? suggestion]) async {
    final query = (suggestion ?? _controller.text).trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    final generation = ++_generation;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    setState(() {
      _submitted = true;
      _loading = true;
      _failed = false;
      _suggestions = const [];
      _works = const [];
    });
    try {
      final works = await _service.search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _works = works;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchLabel = _zh ? '搜索' : 'Search';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          maxLength: 128,
          onChanged: _changed,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: AppL10n.of(context).communitySearchHint,
            counterText: '',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: _zh ? '清除' : 'Clear',
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () {
                      _controller.clear();
                      _changed('');
                      _focus.requestFocus();
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _controller.text.trim().isEmpty ? null : () => _search(),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: Text(searchLabel),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }
    if (_failed) {
      return Center(
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: () => _submitted ? _search() : _changed(_controller.text),
          child: Text(_zh ? '搜索暂不可用，点按重试' : 'Search unavailable. Tap to retry'),
        ),
      );
    }
    if (_submitted && _works.isEmpty) {
      return Center(child: Text(_zh ? '未找到相关作品' : 'No matching works'));
    }
    return ListView.builder(
      itemCount: _submitted ? _works.length : _suggestions.length,
      itemBuilder: (context, index) {
        if (_submitted) {
          final work = _works[index];
          return ListTile(
            title: Text(work.title),
            trailing: const Icon(Icons.chevron_right, color: Colors.black),
            onTap: () => widget.onWorkSelected(work),
          );
        }
        final suggestion = _suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search, color: Colors.grey),
          title: Text(suggestion),
          onTap: () => _search(suggestion),
        );
      },
    );
  }
}
