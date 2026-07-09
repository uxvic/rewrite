using System.Speech.Recognition;

namespace Rewrite.Services;

/// Local, on-device dictation via System.Speech (SpeechRecognitionEngine +
/// DictationGrammar). Raises Recognized with finalized phrases; the caller appends
/// them to the composer. The Windows analog of the macOS SpeechManager (simpler —
/// the OS recognizer does the work). Recognition events arrive on a worker thread.
public sealed class SpeechService : IDisposable
{
    private SpeechRecognitionEngine? _engine;
    public bool IsListening { get; private set; }

    /// A finalized phrase was recognized.
    public event Action<string>? Recognized;
    /// Recognition ended (stopped, or no audio) — lets the UI reset its toggle.
    public event Action? Stopped;

    /// Starts dictation. Returns false if no recognizer or microphone is available.
    public bool Start()
    {
        if (IsListening) return true;
        try
        {
            _engine = new SpeechRecognitionEngine();
            _engine.LoadGrammar(new DictationGrammar());
            _engine.SetInputToDefaultAudioDevice();
            _engine.SpeechRecognized += OnRecognized;
            _engine.RecognizeCompleted += OnCompleted;
            _engine.RecognizeAsync(RecognizeMode.Multiple);
            IsListening = true;
            return true;
        }
        catch
        {
            Cleanup();
            return false;
        }
    }

    public void Stop()
    {
        if (!IsListening) return;
        try { _engine?.RecognizeAsyncStop(); } catch { /* ignore */ }
        IsListening = false;
    }

    private void OnRecognized(object? sender, SpeechRecognizedEventArgs e)
    {
        var text = e.Result?.Text;
        if (!string.IsNullOrWhiteSpace(text)) Recognized?.Invoke(text!);
    }

    private void OnCompleted(object? sender, RecognizeCompletedEventArgs e)
    {
        IsListening = false;
        Stopped?.Invoke();
    }

    private void Cleanup()
    {
        if (_engine is not null)
        {
            try { _engine.RecognizeAsyncStop(); } catch { /* ignore */ }
            _engine.SpeechRecognized -= OnRecognized;
            _engine.RecognizeCompleted -= OnCompleted;
            _engine.Dispose();
            _engine = null;
        }
        IsListening = false;
    }

    public void Dispose() => Cleanup();
}
