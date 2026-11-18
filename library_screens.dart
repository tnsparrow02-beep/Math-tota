import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_helper.dart';
import 'strings.dart';
import 'widgets.dart';

// ───────────────────────── Helpers ─────────────────────────

/// "2026/2027" for a date between September 2026 and August 2027.
String currentAcademicYear([DateTime? now]) {
  final d = now ?? DateTime.now();
  final start = d.month >= 9 ? d.year : d.year - 1;
  return '$start/${start + 1}';
}

/// Folder keys: 'general', 'ctrl1'..'ctrl6' (continuous assessments), 'synth1'..'synth3'.
String folderTitle(BuildContext context, String key) {
  if (key == 'general') return context.t('libMyFiles');
  if (key.startsWith('ctrl')) return '${context.t('ctrlName')} ${key.substring(4)}';
  if (key.startsWith('synth')) return '${context.t('synthName')} ${key.substring(5)}';
  return key;
}

/// 'pdf' / 'word' / 'image', or null when the extension is not allowed.
String? kindForExtension(String ext) {
  switch (ext.toLowerCase()) {
    case '.pdf':
      return 'pdf';
    case '.doc':
    case '.docx':
      return 'word';
    case '.jpg':
    case '.jpeg':
    case '.png':
      return 'image';
    default:
      return null;
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _safeName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

Future<Directory> _folderDir(String year, String folder) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'library', year.replaceAll('/', '-'), folder));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

// ───────────────────────── Tab: My library (academic years) ─────────────────────────

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _db = DatabaseHelper.instance;
  List<String> _years = [];
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var years = await _db.getLibraryYears();
    if (years.isEmpty) {
      // First opening: create the current academic year automatically.
      await _db.addLibraryYear(currentAcademicYear());
      years = await _db.getLibraryYears();
    }
    final counts = await _db.getLibraryYearCounts();
    if (!mounted) return;
    setState(() {
      _years = years;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _addYear() async {
    final start = int.parse(currentAcademicYear().substring(0, 4));
    final candidates = [
      for (var y = start + 3; y >= start - 4; y--) '$y/${y + 1}',
    ].where((y) => !_years.contains(y)).toList();

    final picked = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('addYear')),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final y in candidates)
                ActionChip(
                  label: Text(y, style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => Navigator.pop(c, y),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('cancel'))),
        ],
      ),
    );
    if (picked == null) return;
    await _db.addLibraryYear(picked);
    _load();
  }

  Future<void> _deleteYear(String year) async {
    final ok = await confirmDialog(
      context,
      title: '${context.t('deleteYear')}  $year',
      body: context.t('deleteYearBody'),
      confirmLabel: context.t('delete'),
    );
    if (!ok) return;
    final paths = await _db.deleteLibraryYear(year);
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {/* the database row is already gone; ignore a file that cannot be removed */}
    }
    _load();
  }

  Future<void> _open(String year) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => YearScreen(year: year)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addYear,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('addYear')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _years.length,
              itemBuilder: (_, i) {
                final year = _years[i];
                return SoftCard(
                  onTap: () => _open(year),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.indigo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.school_rounded, color: AppColors.indigo, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t('academicYear'),
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                            Text(
                              year,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '${_counts[year] ?? 0} ${context.t('filesCount')}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (_) => _deleteYear(year),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              context.t('deleteYear'),
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ───────────────────────── One academic year ─────────────────────────

class YearScreen extends StatefulWidget {
  final String year;
  const YearScreen({super.key, required this.year});

  @override
  State<YearScreen> createState() => _YearScreenState();
}

class _YearScreenState extends State<YearScreen> {
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await DatabaseHelper.instance.getLibraryFolderCounts(widget.year);
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  Future<void> _go(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    var exams = 0;
    _counts.forEach((key, value) {
      if (key.startsWith('ctrl') || key.startsWith('synth')) exams += value;
    });

    return Scaffold(
      appBar: AppBar(title: Text('${context.t('navLibrary')}  ·  ${widget.year}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BigTile(
            icon: Icons.folder_special_rounded,
            color: AppColors.amber,
            title: context.t('examsTitle'),
            subtitle: '$exams ${context.t('filesCount')}',
            onTap: () => _go(ExamsScreen(year: widget.year)),
          ),
          _BigTile(
            icon: Icons.folder_rounded,
            color: AppColors.indigo,
            title: context.t('libMyFiles'),
            subtitle: '${_counts['general'] ?? 0} ${context.t('filesCount')}',
            onTap: () => _go(
              FolderFilesScreen(year: widget.year, folder: 'general'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BigTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.indigo),
        ],
      ),
    );
  }
}

// ───────────────────────── Exams: two main icons ─────────────────────────

class ExamsScreen extends StatefulWidget {
  final String year;
  const ExamsScreen({super.key, required this.year});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await DatabaseHelper.instance.getLibraryFolderCounts(widget.year);
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  int _sum(String prefix) {
    var total = 0;
    _counts.forEach((key, value) {
      if (key.startsWith(prefix)) total += value;
    });
    return total;
  }

  Future<void> _go(bool control) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExamFoldersScreen(year: widget.year, control: control)),
    );
    _load();
  }

  Widget _square(IconData icon, Color color, String title, int count, VoidCallback onTap) {
    return Expanded(
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 46, color: color),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('$count ${context.t('filesCount')}', style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${context.t('examsTitle')}  ·  ${widget.year}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _square(
              Icons.assignment_turned_in_rounded,
              AppColors.indigo,
              context.t('ctrlTitle'),
              _sum('ctrl'),
              () => _go(true),
            ),
            const SizedBox(width: 12),
            _square(
              Icons.workspace_premium_rounded,
              AppColors.emerald,
              context.t('synthTitle'),
              _sum('synth'),
              () => _go(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 6 continuous assessments (فرض مراقبة عدد 1..6) or the 3 synthesis exams (فرض تأليفي عدد 1..3).
class ExamFoldersScreen extends StatefulWidget {
  final String year;
  final bool control;
  const ExamFoldersScreen({super.key, required this.year, required this.control});

  @override
  State<ExamFoldersScreen> createState() => _ExamFoldersScreenState();
}

class _ExamFoldersScreenState extends State<ExamFoldersScreen> {
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await DatabaseHelper.instance.getLibraryFolderCounts(widget.year);
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.control ? 'ctrl' : 'synth';
    final total = widget.control ? 6 : 3;
    final color = widget.control ? AppColors.indigo : AppColors.emerald;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${context.t(widget.control ? 'ctrlTitle' : 'synthTitle')}  ·  ${widget.year}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var n = 1; n <= total; n++)
            SoftCard(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderFilesScreen(year: widget.year, folder: '$prefix$n'),
                  ),
                );
                _load();
              },
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$n',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      folderTitle(context, '$prefix$n'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 16, color: color),
                        Text(
                          '${_counts['$prefix$n'] ?? 0}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.indigo),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Files of one folder ─────────────────────────

class FolderFilesScreen extends StatefulWidget {
  final String year;
  final String folder;
  const FolderFilesScreen({super.key, required this.year, required this.folder});

  @override
  State<FolderFilesScreen> createState() => _FolderFilesScreenState();
}

class _FolderFilesScreenState extends State<FolderFilesScreen> {
  final _db = DatabaseHelper.instance;
  List<LibraryFile> _files = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await _db.getLibraryFiles(widget.year, widget.folder);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  /// Copies [source] into the app's private storage and records it in the database.
  Future<bool> _store(XFile source, String displayName) async {
    final kind = kindForExtension(p.extension(displayName));
    if (kind == null) return false;
    final dir = await _folderDir(widget.year, widget.folder);
    final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${_safeName(displayName)}');
    await source.saveTo(dest);
    final size = await File(dest).length();
    await _db.insertLibraryFile(
      year: widget.year,
      folder: widget.folder,
      name: displayName,
      path: dest,
      kind: kind,
      size: size,
    );
    return true;
  }

  Future<void> _addFiles() async {
    setState(() => _busy = true);
    try {
      final group = XTypeGroup(
        label: 'Documents',
        extensions: const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        mimeTypes: const [
          'application/pdf',
          'application/msword',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'image/jpeg',
          'image/png',
        ],
      );
      final picked = await openFiles(acceptedTypeGroups: [group]);
      var rejected = 0;
      for (final f in picked) {
        if (!await _store(f, f.name)) rejected++;
      }
      if (rejected > 0 && mounted) showSnack(context, context.t('fileTypeRejected'));
    } catch (_) {
      if (mounted) showSnack(context, context.t('fileAddFail'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  String _photoName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'IMG_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}.jpg';
  }

  Future<void> _takePhoto() async {
    setState(() => _busy = true);
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2600,
      );
      if (shot != null) await _store(shot, _photoName());
    } catch (_) {
      if (mounted) showSnack(context, context.t('fileAddFail'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _open(LibraryFile f) async {
    final exists = await File(f.path).exists();
    if (!mounted) return;
    if (!exists) {
      showSnack(context, context.t('fileMissing'));
      return;
    }
    if (f.kind == 'image') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _ImageViewer(path: f.path, title: f.name)),
      );
      return;
    }
    final result = await OpenFilex.open(f.path);
    if (result.type != ResultType.done && mounted) {
      showSnack(context, context.t('fileOpenFail'));
    }
  }

  Future<void> _delete(LibraryFile f) async {
    final ok = await confirmDialog(
      context,
      title: context.t('confirmDelete'),
      body: f.name,
      confirmLabel: context.t('delete'),
    );
    if (!ok) return;
    await _db.deleteLibraryFile(f.id!);
    try {
      final file = File(f.path);
      if (await file.exists()) await file.delete();
    } catch (_) {/* ignore */}
    _load();
  }

  Widget _leading(LibraryFile f) {
    if (f.kind == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(f.path),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          cacheWidth: 168,
          errorBuilder: (_, __, ___) => _iconBox(Icons.image_rounded, AppColors.emerald),
        ),
      );
    }
    return f.kind == 'pdf'
        ? _iconBox(Icons.picture_as_pdf_rounded, AppColors.danger)
        : _iconBox(Icons.description_rounded, const Color(0xFF2563EB));
  }

  Widget _iconBox(IconData icon, Color color) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 30),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              folderTitle(context, widget.folder),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            Text(
              widget.year,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : _addFiles,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(context.t('uploadFile')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _takePhoto,
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: Text(context.t('takePhoto')),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? EmptyState(icon: Icons.folder_open_rounded, message: context.t('noFiles'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _files.length,
                        itemBuilder: (_, i) {
                          final f = _files[i];
                          return SoftCard(
                            onTap: () => _open(f),
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                _leading(f),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        f.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        '${formatFileSize(f.size)}  ·  ${f.added.length >= 10 ? f.added.substring(0, 10) : f.added}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.t('delete'),
                                  onPressed: () => _delete(f),
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String path;
  final String title;
  const _ImageViewer({required this.path, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
