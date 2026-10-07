import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/time_extensions.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/order_toggle_button.dart';
import '../../domain/models/pdf_library_item.dart';
import '../providers/pdf_library_provider.dart';

@RoutePage()
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// The library is stored newest-first, so the list starts
  /// descending and the button flips it to oldest-first.
  var _descending = true;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(pdfLibraryProvider);
    final hasEntries = library.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          OrderToggleButton(
            descending: _descending,
            onToggle: () => setState(() => _descending = !_descending),
          ),
        ],
      ),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load library',
              subtitle: '$error',
            ),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No PDFs yet',
              subtitle: 'Import a PDF to read it here.',
              action: FilledButton.icon(
                onPressed: () => _pickAndAdd(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add PDF'),
              ),
            );
          }

          final ordered = _descending ? entries : entries.reversed.toList();

          return ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = ordered[index];

              return ListTile(
                leading: const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.picture_as_pdf_outlined, size: 20),
                ),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _subtitle(entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed:
                      () => ref
                          .read(pdfLibraryProvider.notifier)
                          .remove(entry.path),
                ),
                onTap:
                    () => context.router.push(
                      PdfReaderRoute(
                        path: entry.path,
                        title: entry.title,
                        initialPage: entry.lastPage,
                      ),
                    ),
              );
            },
          );
        },
      ),
      floatingActionButton:
          hasEntries
              ? FloatingActionButton(
                tooltip: 'Add PDF',
                onPressed: () => _pickAndAdd(context, ref),
                child: const Icon(Icons.add),
              )
              : null,
    );
  }

  String _subtitle(PdfLibraryItem entry) {
    final added = entry.addedAt.relativeTime;

    if (entry.pageCount > 0) {
      return 'Page ${entry.lastPage} of ${entry.pageCount} · $added';
    }

    return added;
  }

  Future<void> _pickAndAdd(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await ref.read(pdfPickerProvider).pick();
      if (picked == null) {
        return;
      }

      final item = await ref
          .read(pdfLibraryProvider.notifier)
          .add(sourcePath: picked.path, fileName: picked.name);

      if (!context.mounted) {
        return;
      }

      context.router.push(
        PdfReaderRoute(
          path: item.path,
          title: item.title,
          initialPage: item.lastPage,
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add PDF: $error')));
    }
  }
}
