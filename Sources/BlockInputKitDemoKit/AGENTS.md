# BlockInputKitDemoKit

Extensible core-only demo library: the demo shell, model, window/app delegate, data, and the `DemoEditorExtension` seam through which a host wires plugins. No plugin imports here — plugin grammar/policy is supplied by the executable's `BundledDemoEditorExtension` (or any host conformer). Keep this target plugin-free; thread host-selected inputs (e.g. `chipTagStyle`) through `DemoExtensionContext` rather than importing plugin types.
