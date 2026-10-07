# Silero VAD (CoreML)

`silero-vad-unified-v6.0.0.mlmodelc` is Silero VAD v6.0.0 converted to CoreML
by FluidInference, unmodified.

- Source: https://huggingface.co/FluidInference/silero-vad-coreml
  (revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`, published under the MIT license)
- Original model: https://github.com/snakers4/silero-vad
- Used by `Voce/Core/Audio/VoiceActivityDetector.swift`: 576-sample input
  (64 context + 512 new samples at 16 kHz), LSTM state 2 × [1, 128],
  output `vad_output` = speech probability for the 32 ms frame.

SHA-256 of the files as downloaded:

```
282b1b788b5d4d66d6a70d468464a7ada71d2469a8705526b741fd9ab841295a  metadata.json
79eea23c368f3e7edf85af798a953f5b0910e4b08ff48e55fff8545dd05fd047  model.mil
f460dcdf796b19c04bc38ab6e69601831f634e5e74d499487f0c8fe17ca12f0f  coremldata.bin
853cf34740d3f5061f977ebe2976f7c921b064261c9c4753b3a1196f2dba42b4  weights/weight.bin
2141be60ea0adf7acb1232fbcfaffb2be308ae02e6672d3762aedf36611ea9fd  analytics/coremldata.bin
```

## License

MIT License

Copyright (c) 2020-present Silero Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
