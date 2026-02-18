using RecorderPhone.Windows.Models;

namespace RecorderPhone.Windows.Services;

public sealed class IngestEventStore
{
    public event EventHandler<IngestEvent>? EventReceived;

    public void Add(IngestEvent e)
    {
        EventReceived?.Invoke(this, e);
    }
}

