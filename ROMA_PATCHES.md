# Roma Qwen frontend corrections

Based on Blaizzy/mlx-audio-swift commit
`bf14ae0c26e4e85553dd989571cae29d70fa6735`. Original MIT license retained.

Three narrow corrections preserve the model's trained preprocessing:

1. Qwen encoder output lengths count complete 100-frame chunks with integer
   division. MLX `/` performs true division, so a partial chunk previously added
   padded encoder positions to the valid-audio count. `floorDiv` matches the
   original Qwen formula. For 225 input frames, the valid count is 30, not 33.
2. Incremental mel preprocessing uses Slaney mel scale and periodic Hann,
   matching the existing corrected batch frontend. Area normalization alone
   does not select Slaney's frequency scale.

3. Incremental processing buffers packets until one complete FFT frame exists.
   Swift integer division truncates negative values toward zero, so the previous
   frame count could request 400 samples from a 241–399-sample allocation.

`QwenFrontendRegressionTests` checks all positive lengths through 800 frames
against independently computed convolution output dimensions and compares
batch/incremental interior mel frames from a deterministic waveform. These
numerical tests require an MLX-compatible environment and no downloaded model.

No architecture, tokenizer, language policy, or decoding parameters change.
Roma pins a reviewed commit rather than modifying dependency sources during builds.

## Automatic-language streaming text

A follow-up based on fork commit `9adf5b35d1e15119785e7bc1b531877ee680f7dc`
factors Qwen's existing response-header parser into `QwenTranscriptionText`.
Streaming now parses each encoder window before displaying or joining its text.
An unfinished automatic-language header remains hidden even when decoding stops;
explicit-language generation remains ordinary dictation. Batch text without a
header retains its existing fallback. Literal header-like text inside an actual
transcript is preserved.

The existing window-joining helpers move into the same Foundation-only module
without changing their overlap rules. Joining the full window before splitting
confirmed and provisional text preserves spaces and overlap handling when the
confirmation boundary lies inside a header. Raw token arrays, token confirmation,
cache handling, and window-reset decisions do not depend on parsed display text.

`QwenTranscriptionTextTests` covers both languages, code switching, literal words,
every partial/final header boundary, cross-header confirmation splits, explicit
language, window joining, overlap, and Unicode boundaries. The actual parser and
all 12 test bodies passed a local Foundation assertion harness. The local Command
Line Tools installation lacks the `Testing` module; full Swift Testing execution,
MLX compilation, and native streaming replay remain separate required gates.
