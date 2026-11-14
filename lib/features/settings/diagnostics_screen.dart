import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/diagnostic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/tv_focus.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _selectedTag = 'ALL';
  bool _onlyErrors = false;
  String _searchQuery = '';
  bool _autoScroll = false;

  final DiagnosticService _diagnostics = DiagnosticService.instance;

  @override
  void initState() {
    super.initState();
    _diagnostics.addListener(_onLogsUpdated);
  }

  @override
  void dispose() {
    _diagnostics.removeListener(_onLogsUpdated);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsUpdated() {
    if (mounted) {
      setState(() {});
      if (_autoScroll && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  List<LogEntry> _filterLogs(List<LogEntry> all) {
    return all.where((e) {
      if (_onlyErrors && e.level != LogLevel.error) {
        return false;
      }
      if (_selectedTag != 'ALL' && e.tag.toLowerCase() != _selectedTag.toLowerCase()) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final inMsg = e.message.toLowerCase().contains(q);
        final inTag = e.tag.toLowerCase().contains(q);
        final inDetails = e.details?.toLowerCase().contains(q) ?? false;
        if (!inMsg && !inTag && !inDetails) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = _diagnostics.logs;
    final filtered = _filterLogs(allLogs);

    // Extract unique tags
    final tags = <String>{'ALL'};
    for (final l in allLogs) {
      tags.add(l.tag);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic Logs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Streaming resolver & runtime telemetry',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Full Report',
            icon: const Icon(Icons.copy_all_rounded, color: AppColors.secondary),
            onPressed: () => _diagnostics.copyReportToClipboard(context),
          ),
          IconButton(
            tooltip: 'Clear Logs',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
            onPressed: _confirmClear,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Stat Banner ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surfaceContainerLow,
            child: Row(
              children: [
                _buildStatPill('Total', '${allLogs.length}', Colors.blueGrey),
                const SizedBox(width: 8),
                _buildStatPill('Errors', '${_diagnostics.errorCount}', AppColors.error,
                    isHighlight: _diagnostics.errorCount > 0),
                const SizedBox(width: 8),
                _buildStatPill('Warnings', '${_diagnostics.warningCount}', Colors.amber),
                const SizedBox(width: 8),
                _buildStatPill('Success', '${_diagnostics.successCount}', Colors.greenAccent),
                const Spacer(),
                TvFocusable(
                  semanticLabel: 'Live auto-scroll',
                  borderRadius: 8,
                  onSelect: () => setState(() => _autoScroll = !_autoScroll),
                  child: GestureDetector(
                    onTap: () => setState(() => _autoScroll = !_autoScroll),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _autoScroll
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              _autoScroll ? AppColors.primary : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.vertical_align_bottom_rounded,
                            size: 14,
                            color: _autoScroll
                                ? AppColors.secondary
                                : Colors.white60,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _autoScroll
                                  ? AppColors.secondary
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Search & Filter Controls ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            color: AppColors.surfaceContainerLow,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter by message, URL, error or tag…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white54),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white54),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        selected: _onlyErrors,
                        label: Text(
                          'Errors only (${_diagnostics.errorCount})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _onlyErrors ? Colors.white : AppColors.error,
                          ),
                        ),
                        selectedColor: AppColors.error,
                        backgroundColor: AppColors.error.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        side: const BorderSide(color: AppColors.error),
                        onSelected: (val) => setState(() => _onlyErrors = val),
                      ),
                      const SizedBox(width: 8),
                      for (final tag in tags) ...[
                        ChoiceChip(
                          selected: _selectedTag.toUpperCase() == tag.toUpperCase(),
                          label: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _selectedTag.toUpperCase() == tag.toUpperCase()
                                  ? Colors.black
                                  : Colors.white70,
                            ),
                          ),
                          selectedColor: AppColors.secondary,
                          backgroundColor: AppColors.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide.none,
                          onSelected: (sel) {
                            if (sel) setState(() => _selectedTag = tag);
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Log list ─────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 48, color: Colors.white24),
                        const SizedBox(height: 12),
                        Text(
                          allLogs.isEmpty
                              ? 'No logs recorded yet.\nAttempt a stream or download to see live events.'
                              : 'No logs match your filter criteria.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildLogCard(item);
                    },
                  ),
          ),

          // ── Bottom Quick Action Bar ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(top: BorderSide(color: AppColors.surfaceContainerHighest)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _diagnostics.copyReportToClipboard(context),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text(
                      'Copy Diagnostic Report',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight ? color : Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(LogEntry item) {
    Color levelColor;
    IconData levelIcon;

    switch (item.level) {
      case LogLevel.error:
        levelColor = AppColors.error;
        levelIcon = Icons.error_outline_rounded;
        break;
      case LogLevel.warning:
        levelColor = Colors.amber;
        levelIcon = Icons.warning_amber_rounded;
        break;
      case LogLevel.success:
        levelColor = Colors.greenAccent;
        levelIcon = Icons.check_circle_outline_rounded;
        break;
      case LogLevel.debug:
        levelColor = Colors.white38;
        levelIcon = Icons.bug_report_outlined;
        break;
      case LogLevel.info:
        levelColor = Colors.cyanAccent;
        levelIcon = Icons.info_outline_rounded;
        break;
    }

    final tagColor = _getTagColor(item.tag);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: item.level == LogLevel.error
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.level == LogLevel.error
              ? AppColors.error.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: TvFocusable(
        onSelect: () => _showEntryDetails(item),
        semanticLabel: item.message,
        scale: 1.01,
        borderRadius: 8,
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showEntryDetails(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(levelIcon, size: 14, color: levelColor),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: tagColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Text(
                      item.tag,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tagColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.formattedTime,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                item.message,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: item.level == LogLevel.error
                      ? const Color(0xFFFF8585)
                      : item.level == LogLevel.success
                          ? Colors.greenAccent
                          : Colors.white.withValues(alpha: 0.9),
                  height: 1.35,
                ),
              ),
              if (item.details != null && item.details!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.details!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'streamresolver':
        return Colors.lightBlueAccent;
      case 'webview':
        return Colors.purpleAccent;
      case 'mediadelivery':
        return Colors.orangeAccent;
      case 'videoplayer':
        return Colors.tealAccent;
      default:
        return Colors.blueGrey;
    }
  }

  void _showEntryDetails(LogEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scroll,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    entry.tag,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _getTagColor(entry.tag),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    entry.formattedTime,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  entry.message,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
              if (entry.details != null && entry.details!.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Details & Stack Trace',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SelectableText(
                    entry.details!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  final text = '${entry.formattedTime} [${entry.tag}] ${entry.message}\n${entry.details ?? ""}';
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Entry copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy This Entry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Clear all logs?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will wipe all stored diagnostic events. Are you sure?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _diagnostics.clear();
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
