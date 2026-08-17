using Godot;
using Godot.Collections;
using System;
using System.Collections.Generic;
using System.Diagnostics;

[GlobalClass]
public partial class ChunkMesherCs : RefCounted
{
    private const int SizeXz = 16;
    private const int Height = 64;
    private const int CollisionRegionSize = 16;
    private const int CollisionRegionCountY = Height / CollisionRegionSize;
    private const int Air = 0;
    private const int Grass = 1;
    private const int Dirt = 2;
    private const int Stone = 3;
    private const int Bedrock = 4;
    private const int Wood = 5;
    private const int Leaves = 6;
    private const int Water = 7;
    private const int Sand = 8;
    private const int Coal = 9;
    private const int Iron = 10;
    private const int Copper = 11;
    private const int Tin = 12;
    private const int Gold = 13;
    private const int Tungsten = 14;
    private const int Platinum = 15;
    private const int WoodPlanks = 16;
    private const int Workbench = 19;
    private const int Furnace = 20;
    private const int Torch = 21;

    private static readonly Vector3I[] Directions =
    {
        Vector3I.Up, Vector3I.Down, Vector3I.Right, Vector3I.Left,
        new(0, 0, 1), new(0, 0, -1),
    };

    private static readonly Vector3[][] FaceVertices =
    {
        new[] { new Vector3(0, 1, 0), new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 1, 0) },
        new[] { new Vector3(0, 0, 1), new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(1, 0, 1) },
        new[] { new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1) },
        new[] { new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0), new Vector3(0, 0, 0) },
        new[] { new Vector3(1, 0, 1), new Vector3(1, 1, 1), new Vector3(0, 1, 1), new Vector3(0, 0, 1) },
        new[] { new Vector3(0, 0, 0), new Vector3(0, 1, 0), new Vector3(1, 1, 0), new Vector3(1, 0, 0) },
    };

    public Dictionary BuildMeshData(Dictionary snapshot)
    {
        int gcGen0Before = GC.CollectionCount(0);
        int gcGen1Before = GC.CollectionCount(1);
        int gcGen2Before = GC.CollectionCount(2);
        long allocatedBytesBefore = GC.GetTotalAllocatedBytes(false);
        long managedMemoryBefore = GC.GetTotalMemory(false);
        var stopwatch = Stopwatch.StartNew();
        int[] blocks = snapshot["blocks_flat"].AsInt32Array();
        byte[] blockLight = snapshot["block_light_flat"].AsByteArray();
        byte[] sunLight = snapshot["sun_light_flat"].AsByteArray();
        int[] negativeX = snapshot["negative_x"].AsInt32Array();
        int[] positiveX = snapshot["positive_x"].AsInt32Array();
        int[] negativeZ = snapshot["negative_z"].AsInt32Array();
        int[] positiveZ = snapshot["positive_z"].AsInt32Array();
        byte[] negativeXLight = snapshot["negative_x_light"].AsByteArray();
        byte[] positiveXLight = snapshot["positive_x_light"].AsByteArray();
        byte[] negativeZLight = snapshot["negative_z_light"].AsByteArray();
        byte[] positiveZLight = snapshot["positive_z_light"].AsByteArray();
        byte[] negativeXSun = snapshot["negative_x_sun"].AsByteArray();
        byte[] positiveXSun = snapshot["positive_x_sun"].AsByteArray();
        byte[] negativeZSun = snapshot["negative_z_sun"].AsByteArray();
        byte[] positiveZSun = snapshot["positive_z_sun"].AsByteArray();

        var vertices = new List<Vector3>();
        var normals = new List<Vector3>();
        var uvs = new List<Vector2>();
        var colors = new List<Color>();
        var indices = new List<int>();

        for (int x = 0; x < SizeXz; x++)
        for (int y = 0; y < Height; y++)
        for (int z = 0; z < SizeXz; z++)
        {
            int block = blocks[Index(x, y, z)];
            if (!IsMeshBlock(block))
                continue;
            for (int face = 0; face < Directions.Length; face++)
            {
                Vector3I direction = Directions[face];
                int nx = x + direction.X;
                int ny = y + direction.Y;
                int nz = z + direction.Z;
                if (IsMeshBlock(GetBlock(blocks, negativeX, positiveX, negativeZ, positiveZ, nx, ny, nz)))
                    continue;
                AddFace(vertices, normals, uvs, colors, indices, x, y, z, face, block,
                    GetLight(blockLight, negativeXLight, positiveXLight, negativeZLight, positiveZLight, nx, ny, nz, false),
                    GetLight(sunLight, negativeXSun, positiveXSun, negativeZSun, positiveZSun, nx, ny, nz, true));
            }
        }

        var collisionUnits = BuildCollisionUnits(blocks, snapshot["collision_unit_indices"].AsGodotArray());
        Vector3[] vertexArray = vertices.ToArray();
        Vector3[] normalArray = normals.ToArray();
        Vector2[] uvArray = uvs.ToArray();
        Color[] colorArray = colors.ToArray();
        int[] indexArray = indices.ToArray();
        stopwatch.Stop();
        int gcGen0After = GC.CollectionCount(0);
        int gcGen1After = GC.CollectionCount(1);
        int gcGen2After = GC.CollectionCount(2);
        long allocatedBytesAfter = GC.GetTotalAllocatedBytes(false);
        long managedMemoryAfter = GC.GetTotalMemory(false);
        return new Dictionary
        {
            ["vertices"] = vertexArray, ["normals"] = normalArray,
            ["uvs"] = uvArray, ["colors"] = colorArray,
            ["indices"] = indexArray, ["collision_units"] = collisionUnits,
            ["worker_usec"] = (long)(stopwatch.Elapsed.TotalMilliseconds * 1000.0),
            ["gc_gen0"] = gcGen0After - gcGen0Before,
            ["gc_gen1"] = gcGen1After - gcGen1Before,
            ["gc_gen2"] = gcGen2After - gcGen2Before,
            ["managed_allocated_bytes"] = allocatedBytesAfter - allocatedBytesBefore,
            ["managed_memory_before"] = managedMemoryBefore,
            ["managed_memory_after"] = managedMemoryAfter,
        };
    }

    private static bool IsMeshBlock(int block) => block != Air && block != Torch;
    private static int Index(int x, int y, int z) => (y * SizeXz + z) * SizeXz + x;

    private static int GetBlock(int[] center, int[] nx, int[] px, int[] nz, int[] pz, int x, int y, int z)
    {
        if (y < 0 || y >= Height) return Air;
        if (x >= 0 && x < SizeXz && z >= 0 && z < SizeXz) return center[Index(x, y, z)];
        if (x < 0) return nx[y * SizeXz + z];
        if (x >= SizeXz) return px[y * SizeXz + z];
        if (z < 0) return nz[y * SizeXz + x];
        return pz[y * SizeXz + x];
    }

    private static int GetLight(byte[] center, byte[] nx, byte[] px, byte[] nz, byte[] pz, int x, int y, int z, bool sunlight)
    {
        if (y >= Height) return sunlight ? 15 : 0;
        if (y < 0) return 0;
        if (x >= 0 && x < SizeXz && z >= 0 && z < SizeXz) return center[Index(x, y, z)];
        if (x < 0) return nx[y * SizeXz + z];
        if (x >= SizeXz) return px[y * SizeXz + z];
        if (z < 0) return nz[y * SizeXz + x];
        return pz[y * SizeXz + x];
    }

    private static void AddFace(List<Vector3> vertices, List<Vector3> normals, List<Vector2> uvs,
        List<Color> colors, List<int> indices, int x, int y, int z, int face, int block, int blockLight, int sunLight)
    {
        int start = vertices.Count;
        Vector2I tile = GetTexture(block, face);
        float left = tile.X / 16.0f, right = (tile.X + 1) / 16.0f;
        float top = tile.Y / 16.0f, bottom = (tile.Y + 1) / 16.0f;
        Vector2[] faceUvs = { new(left, bottom), new(left, top), new(right, top), new(right, bottom) };
        float blockBrightness = MathF.Pow(Math.Clamp(blockLight, 0, 15) / 15.0f, 1.35f);
        float sunBrightness = MathF.Pow(Math.Clamp(sunLight, 0, 15) / 15.0f, 1.2f);
        for (int i = 0; i < 4; i++)
        {
            vertices.Add(new Vector3(x, y, z) + FaceVertices[face][i]);
            normals.Add(Directions[face]);
            uvs.Add(faceUvs[i]);
            colors.Add(new Color(blockBrightness, sunBrightness, 0, 1));
        }
        indices.Add(start); indices.Add(start + 2); indices.Add(start + 1);
        indices.Add(start); indices.Add(start + 3); indices.Add(start + 2);
    }

    private static Vector2I GetTexture(int block, int face) => block switch
    {
        Grass => face == 0 ? new(1, 0) : face == 1 ? new(0, 0) : new(2, 0),
        Dirt => new(0, 0), Stone => new(4, 0), Bedrock => new(5, 0),
        Wood => face is 0 or 1 ? new(8, 0) : new(6, 0),
        Leaves => new(7, 0), Water => new(9, 0), Sand => new(10, 0),
        Coal => new(11, 0), Iron => new(12, 0), Copper => new(13, 0),
        Tin => new(14, 0), Gold => new(15, 0), Tungsten => new(1, 1),
        Platinum => new(2, 1), WoodPlanks => new(3, 1), Workbench => new(6, 1),
        Furnace => new(8, 1), _ => new(0, 0),
    };

    private static Godot.Collections.Array BuildCollisionUnits(int[] blocks, Godot.Collections.Array requestedUnits)
    {
        var units = new Godot.Collections.Array();
        foreach (Variant value in requestedUnits)
        {
            int unitY = value.AsInt32();
            if (unitY < 0 || unitY >= CollisionRegionCountY) continue;
            var timer = Stopwatch.StartNew();
            int yMin = unitY * CollisionRegionSize;
            int yMax = Math.Min(yMin + CollisionRegionSize, Height);
            var visited = new bool[SizeXz * (yMax - yMin) * SizeXz];
            var centers = new List<Vector3>();
            var sizes = new List<Vector3>();
            int solidVoxels = 0;
            for (int y = yMin; y < yMax; y++)
            for (int z = 0; z < SizeXz; z++)
            for (int x = 0; x < SizeXz; x++)
            {
                int vi = CollisionIndex(x, y - yMin, z);
                if (!IsMeshBlock(blocks[Index(x, y, z)])) continue;
                solidVoxels++;
                if (visited[vi]) continue;
                int endX = x + 1;
                while (endX < SizeXz && !visited[CollisionIndex(endX, y - yMin, z)] && IsMeshBlock(blocks[Index(endX, y, z)])) endX++;
                int endZ = z + 1;
                while (endZ < SizeXz && StripAvailable(blocks, visited, x, endX, y, yMin, endZ)) endZ++;
                int endY = y + 1;
                while (endY < yMax && LayerAvailable(blocks, visited, x, endX, z, endZ, endY, yMin)) endY++;
                for (int my = y; my < endY; my++)
                for (int mz = z; mz < endZ; mz++)
                for (int mx = x; mx < endX; mx++) visited[CollisionIndex(mx, my - yMin, mz)] = true;
                var size = new Vector3(endX - x, endY - y, endZ - z);
                sizes.Add(size); centers.Add(new Vector3(x, y, z) + size * 0.5f);
            }
            timer.Stop();
            units.Add(new Dictionary
            {
                ["unit_index"] = unitY, ["centers"] = centers.ToArray(), ["sizes"] = sizes.ToArray(),
                ["solid_voxels"] = solidVoxels, ["worker_usec"] = (long)(timer.Elapsed.TotalMilliseconds * 1000.0),
            });
        }
        return units;
    }

    private static int CollisionIndex(int x, int localY, int z) => (localY * SizeXz + z) * SizeXz + x;
    private static bool StripAvailable(int[] blocks, bool[] visited, int startX, int endX, int y, int yMin, int z)
    {
        for (int x = startX; x < endX; x++)
            if (visited[CollisionIndex(x, y - yMin, z)] || !IsMeshBlock(blocks[Index(x, y, z)])) return false;
        return true;
    }
    private static bool LayerAvailable(int[] blocks, bool[] visited, int startX, int endX, int startZ, int endZ, int y, int yMin)
    {
        for (int z = startZ; z < endZ; z++)
        for (int x = startX; x < endX; x++)
            if (visited[CollisionIndex(x, y - yMin, z)] || !IsMeshBlock(blocks[Index(x, y, z)])) return false;
        return true;
    }
}
