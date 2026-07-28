class Candle {
  final int epoch;
  final double o, h, l, c;
  final bool spike;

  const Candle({
    required this.epoch,
    required this.o,
    required this.h,
    required this.l,
    required this.c,
    this.spike = false,
  });

  Candle copyWith({bool? spike}) => Candle(
        epoch: epoch,
        o: o,
        h: h,
        l: l,
        c: c,
        spike: spike ?? this.spike,
      );
}
