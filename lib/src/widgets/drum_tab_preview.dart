import 'package:flutter/material.dart';

import '../services/drum_tab_builder.dart';
import '../theme.dart';

typedef DrumTabCellToggle =
    void Function(
      int blockIndex,
      String pieceId,
      int measureOffset,
      int slotIndex,
    );

class DrumTabPreview extends StatelessWidget {
  const DrumTabPreview({super.key, required this.document});

  final DrumTabDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final block in document.blocks) ...[
          _TabBlockCard(block: block),
          if (block != document.blocks.last) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class EditableDrumTabEditor extends StatelessWidget {
  const EditableDrumTabEditor({
    super.key,
    required this.document,
    required this.onToggleCell,
  });

  final DrumTabDocument document;
  final DrumTabCellToggle onToggleCell;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (
          var blockIndex = 0;
          blockIndex < document.blocks.length;
          blockIndex++
        ) ...[
          _EditableTabBlockCard(
            blockIndex: blockIndex,
            block: document.blocks[blockIndex],
            onToggleCell: onToggleCell,
          ),
          if (blockIndex != document.blocks.length - 1)
            const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _TabBlockCard extends StatelessWidget {
  const _TabBlockCard({required this.block});

  final DrumTabBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.page.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppPalette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectionArea(
                child: Text(
                  block.lines.join('\n'),
                  style: const TextStyle(
                    color: AppPalette.ink,
                    fontFamily: 'Consolas',
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableTabBlockCard extends StatelessWidget {
  const _EditableTabBlockCard({
    required this.blockIndex,
    required this.block,
    required this.onToggleCell,
  });

  final int blockIndex;
  final DrumTabBlock block;
  final DrumTabCellToggle onToggleCell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidth = block.labelWidth * 12.0 + 22.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.accent.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${block.label} • Click cells to add or remove notes',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppPalette.pageInk,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditableCountRow(block: block, labelWidth: labelWidth),
                  const SizedBox(height: 10),
                  for (final piece in block.pieces) ...[
                    _EditablePieceRow(
                      blockIndex: blockIndex,
                      block: block,
                      piece: piece,
                      labelWidth: labelWidth,
                      onToggleCell: onToggleCell,
                    ),
                    if (piece != block.pieces.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableCountRow extends StatelessWidget {
  const _EditableCountRow({required this.block, required this.labelWidth});

  final DrumTabBlock block;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Count',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppPalette.pageInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        for (final measure in block.measures) ...[
          _MeasureHeader(measure: measure),
          if (measure != block.measures.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _EditablePieceRow extends StatelessWidget {
  const _EditablePieceRow({
    required this.blockIndex,
    required this.block,
    required this.piece,
    required this.labelWidth,
    required this.onToggleCell,
  });

  final int blockIndex;
  final DrumTabBlock block;
  final DrumTabPiece piece;
  final double labelWidth;
  final DrumTabCellToggle onToggleCell;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              piece.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppPalette.pageInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        for (
          var measureOffset = 0;
          measureOffset < block.measures.length;
          measureOffset++
        ) ...[
          _EditableMeasureCells(
            cells: block.measures[measureOffset].pieceCells[piece.id]!,
            activeSymbol: piece.symbol,
            onToggleSlot: (slotIndex) {
              onToggleCell(blockIndex, piece.id, measureOffset, slotIndex);
            },
          ),
          if (measureOffset != block.measures.length - 1)
            const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _MeasureHeader extends StatelessWidget {
  const _MeasureHeader({required this.measure});

  final DrumTabMeasureSegment measure;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5E7D2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6BB92)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'M${measure.measureIndex + 1}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.pageInk,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final token in measure.countTokens)
                  _CountTokenCell(token: token),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableMeasureCells extends StatelessWidget {
  const _EditableMeasureCells({
    required this.cells,
    required this.activeSymbol,
    required this.onToggleSlot,
  });

  final List<String> cells;
  final String activeSymbol;
  final ValueChanged<int> onToggleSlot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCC8A9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            for (var slotIndex = 0; slotIndex < cells.length; slotIndex++)
              _EditableCell(
                value: cells[slotIndex],
                fallbackSymbol: activeSymbol,
                onTap: () => onToggleSlot(slotIndex),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditableCell extends StatelessWidget {
  const _EditableCell({
    required this.value,
    required this.fallbackSymbol,
    required this.onTap,
  });

  final String value;
  final String fallbackSymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = value != '-';
    final text = isActive ? value : fallbackSymbol;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? AppPalette.accentSoft : const Color(0xFFF7F0E3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? AppPalette.accent : const Color(0xFFD8C5A9),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isActive ? AppPalette.pageInk : const Color(0xFFB79C79),
                fontFamily: 'Consolas',
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountTokenCell extends StatelessWidget {
  const _CountTokenCell({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF2E4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8C5A9)),
      ),
      child: Text(
        token,
        style: const TextStyle(
          color: AppPalette.pageInk,
          fontFamily: 'Consolas',
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
