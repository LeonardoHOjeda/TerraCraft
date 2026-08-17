using Godot;
using Godot.Collections;
using System;

[GlobalClass]
public partial class GcDiagnosticsCs : RefCounted
{
    public Dictionary Capture()
    {
        return new Dictionary
        {
            ["gen0"] = GC.CollectionCount(0),
            ["gen1"] = GC.CollectionCount(1),
            ["gen2"] = GC.CollectionCount(2),
            ["managed_memory"] = GC.GetTotalMemory(false),
            ["total_allocated_bytes"] = GC.GetTotalAllocatedBytes(false),
        };
    }
}
