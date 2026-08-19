using Godot;
using Godot.Collections;
using System;
using System.Collections.Generic;
using System.Diagnostics;

[GlobalClass]
public partial class ChunkGeneratorCs : RefCounted
{
    private static readonly GDScript ChunkDataScript = GD.Load<GDScript>("res://world/chunks/chunk_data.gd");

    private const int SizeXz = 16;
    private const int Height = 64;
    private const int Volume = SizeXz * Height * SizeXz;

    private const int Air = 0;
    private const int Grass = 1;
    private const int Dirt = 2;
    private const int Stone = 3;
    private const int Bedrock = 4;
    private const int Wood = 5;
    private const int Leaves = 6;
    private const int Sand = 8;
    private const int Coal = 9;
    private const int Iron = 10;
    private const int Copper = 11;
    private const int Tin = 12;
    private const int Gold = 13;
    private const int Tungsten = 14;
    private const int Platinum = 15;
    private const int Torch = 21;

    public Dictionary GenerateData(Dictionary parameters)
    {
        var totalTimer = Stopwatch.StartNew();
        Vector2I chunkPosition = parameters["chunk_position"].AsVector2I();
        var continentalNoise = parameters["continental_noise"].As<FastNoiseLite>();
        var detailNoise = parameters["detail_noise"].As<FastNoiseLite>();
        var biomeNoise = parameters["biome_noise"].As<FastNoiseLite>();
        var treeNoise = parameters["tree_noise"].As<FastNoiseLite>();
        var caveNoise = parameters["cave_noise"].As<FastNoiseLite>();
        var coalNoise = parameters["coal_noise"].As<FastNoiseLite>();
        var ironNoise = parameters["iron_noise"].As<FastNoiseLite>();
        var copperNoise = parameters["copper_noise"].As<FastNoiseLite>();
        var tinNoise = parameters["tin_noise"].As<FastNoiseLite>();
        var goldNoise = parameters["gold_noise"].As<FastNoiseLite>();
        var tungstenNoise = parameters["tungsten_noise"].As<FastNoiseLite>();
        var platinumNoise = parameters["platinum_noise"].As<FastNoiseLite>();
        int terrainHeight = parameters["terrain_height"].AsInt32();
        int baseHeight = parameters["base_height"].AsInt32();
        Dictionary overrides = parameters["overrides"].AsGodotDictionary();

        var blocks = new int[Volume];
        Populate(blocks, chunkPosition, continentalNoise, detailNoise, biomeNoise, caveNoise,
            coalNoise, ironNoise, copperNoise, tinNoise, goldNoise, tungstenNoise, platinumNoise,
            terrainHeight, baseHeight);
        ApplyTrees(blocks, chunkPosition, continentalNoise, detailNoise, biomeNoise, treeNoise,
            terrainHeight, baseHeight);
        ApplyOverrides(blocks, overrides);

        var sunlight = new byte[Volume];
        var directSunMask = new byte[(Volume + 7) / 8];
        SunlightProfile sunlightProfile = InitializeLocalSunlight(blocks, sunlight, directSunMask);
        BuildRelevantIndices(blocks, out int[] specialIndices, out int[] emissiveIndices);
        GodotObject data = CreateChunkData(blocks, sunlight, directSunMask, specialIndices, emissiveIndices);

        totalTimer.Stop();
        return new Dictionary
        {
            ["data"] = data,
            ["worker_usec"] = ToUsec(totalTimer),
            ["override_count"] = overrides.Count,
            ["sunlight_vertical_worker_usec"] = sunlightProfile.VerticalUsec,
            ["sunlight_local_bfs_worker_usec"] = sunlightProfile.BfsUsec,
            ["sunlight_direct_voxels"] = sunlightProfile.DirectVoxels,
            ["sunlight_seed_count"] = sunlightProfile.SeedCount,
            ["sunlight_legacy_seed_count"] = sunlightProfile.LegacySeedCount,
            ["sunlight_processed_voxels"] = sunlightProfile.ProcessedVoxels,
            ["sunlight_queue_pushes"] = sunlightProfile.QueuePushes,
            ["sunlight_duplicate_rejections"] = sunlightProfile.DuplicateRejections,
            ["sunlight_neighbor_operations"] = sunlightProfile.NeighborOperations,
        };
    }

    private static void Populate(int[] blocks, Vector2I chunkPosition, FastNoiseLite continentalNoise,
        FastNoiseLite detailNoise, FastNoiseLite biomeNoise, FastNoiseLite caveNoise,
        FastNoiseLite coalNoise, FastNoiseLite ironNoise, FastNoiseLite copperNoise,
        FastNoiseLite tinNoise, FastNoiseLite goldNoise, FastNoiseLite tungstenNoise,
        FastNoiseLite platinumNoise, int terrainHeight, int baseHeight)
    {
        for (int x = 0; x < SizeXz; x++)
        for (int y = 0; y < Height; y++)
        for (int z = 0; z < SizeXz; z++)
        {
            int worldX = chunkPosition.X * SizeXz + x;
            int worldZ = chunkPosition.Y * SizeXz + z;
            float biomeValue = biomeNoise.GetNoise2D(worldX, worldZ);
            float continental = continentalNoise.GetNoise2D(worldX, worldZ);
            float detail = detailNoise.GetNoise2D(worldX, worldZ);
            int surfaceHeight = Math.Clamp(baseHeight + Mathf.RoundToInt(continental * terrainHeight + detail * 4.0f), 1, Height - 1);
            int surfaceBlock = biomeValue < -0.25f ? Sand : Grass;
            int undergroundBlock = biomeValue < -0.25f ? Sand : Dirt;
            float caveValue = caveNoise.GetNoise3D(worldX, y, worldZ);
            bool isCave = y > 2 && y < surfaceHeight - 4 && caveValue > 0.38f;

            blocks[Index(x, y, z)] = y switch
            {
                0 => Bedrock,
                _ when y > surfaceHeight => Air,
                _ when isCave => Air,
                _ when y == surfaceHeight => surfaceBlock,
                _ when y >= surfaceHeight - 3 => undergroundBlock,
                _ => GetOreBlock(worldX, y, worldZ, coalNoise, ironNoise, copperNoise,
                    tinNoise, goldNoise, tungstenNoise, platinumNoise),
            };
        }
    }

    private static int GetOreBlock(int x, int y, int z, FastNoiseLite coal, FastNoiseLite iron,
        FastNoiseLite copper, FastNoiseLite tin, FastNoiseLite gold, FastNoiseLite tungsten,
        FastNoiseLite platinum)
    {
        if (y <= 45 && coal.GetNoise3D(x, y, z) > 0.58f) return Coal;
        if (y <= 32 && iron.GetNoise3D(x, y, z) > 0.64f) return Iron;
        if (y <= 14 && tungsten.GetNoise3D(x, y, z) > 0.70f) return Tungsten;
        return Stone;
    }

    private static void ApplyTrees(int[] blocks, Vector2I chunkPosition, FastNoiseLite continentalNoise,
        FastNoiseLite detailNoise, FastNoiseLite biomeNoise, FastNoiseLite treeNoise,
        int terrainHeight, int baseHeight)
    {
        const int radius = 2;
        int minX = chunkPosition.X * SizeXz;
        int minZ = chunkPosition.Y * SizeXz;
        int maxX = minX + SizeXz - 1;
        int maxZ = minZ + SizeXz - 1;
        for (int worldX = minX - radius; worldX <= maxX + radius; worldX++)
        for (int worldZ = minZ - radius; worldZ <= maxZ + radius; worldZ++)
        {
            if (!ShouldGenerateTree(worldX, worldZ, biomeNoise, treeNoise)) continue;
            int surfaceY = Math.Clamp(baseHeight + Mathf.RoundToInt(
                continentalNoise.GetNoise2D(worldX, worldZ) * terrainHeight
                + detailNoise.GetNoise2D(worldX, worldZ) * 4.0f), 1, Height - 1);
            CreateTreePart(blocks, chunkPosition, new Vector3I(worldX, surfaceY + 1, worldZ));
        }
    }

    private static bool ShouldGenerateTree(int worldX, int worldZ, FastNoiseLite biomeNoise, FastNoiseLite treeNoise)
    {
        float biomeValue = biomeNoise.GetNoise2D(worldX, worldZ);
        if (biomeValue < -0.25f) return false;
        float value = treeNoise.GetNoise2D(worldX, worldZ);
        float threshold = biomeValue > 0.35f ? 0.45f : 0.72f;
        if (value < threshold) return false;
        const int minimumDistance = 4;
        for (int ox = -minimumDistance; ox <= minimumDistance; ox++)
        for (int oz = -minimumDistance; oz <= minimumDistance; oz++)
        {
            if (ox == 0 && oz == 0) continue;
            if (ox * ox + oz * oz > minimumDistance * minimumDistance) continue;
            if (treeNoise.GetNoise2D(worldX + ox, worldZ + oz) > value) return false;
        }
        return true;
    }

    private static void CreateTreePart(int[] blocks, Vector2I chunkPosition, Vector3I position)
    {
        const int trunkHeight = 4;
        for (int y = 0; y < trunkHeight; y++) SetTreeBlock(blocks, chunkPosition, position + new Vector3I(0, y, 0), Wood);
        Vector3I leavesCenter = position + new Vector3I(0, trunkHeight, 0);
        for (int ox = -2; ox < 3; ox++)
        for (int oy = -2; oy < 2; oy++)
        for (int oz = -2; oz < 3; oz++)
        {
            if (Math.Abs(ox) + Math.Abs(oz) > 3) continue;
            SetTreeBlock(blocks, chunkPosition, leavesCenter + new Vector3I(ox, oy, oz), Leaves);
        }
        SetTreeBlock(blocks, chunkPosition, leavesCenter + new Vector3I(0, 2, 0), Leaves);
    }

    private static void SetTreeBlock(int[] blocks, Vector2I chunkPosition, Vector3I worldPosition, int block)
    {
        int targetChunkX = Mathf.FloorToInt((float)worldPosition.X / SizeXz);
        int targetChunkZ = Mathf.FloorToInt((float)worldPosition.Z / SizeXz);
        if (targetChunkX != chunkPosition.X || targetChunkZ != chunkPosition.Y) return;
        int x = worldPosition.X - chunkPosition.X * SizeXz;
        int y = worldPosition.Y;
        int z = worldPosition.Z - chunkPosition.Y * SizeXz;
        if (x < 0 || x >= SizeXz || y < 0 || y >= Height || z < 0 || z >= SizeXz) return;
        int index = Index(x, y, z);
        if (blocks[index] == Air) blocks[index] = block;
    }

    private static void ApplyOverrides(int[] blocks, Dictionary overrides)
    {
        foreach (Variant key in overrides.Keys)
        {
            Vector3I position = key.AsVector3I();
            if (position.X < 0 || position.X >= SizeXz || position.Y < 0 || position.Y >= Height || position.Z < 0 || position.Z >= SizeXz) continue;
            blocks[Index(position.X, position.Y, position.Z)] = overrides[key].AsInt32();
        }
    }

    private static SunlightProfile InitializeLocalSunlight(int[] blocks, byte[] sunlight, byte[] directMask)
    {
        var verticalTimer = Stopwatch.StartNew();
        var directIndices = new List<int>();
        for (int x = 0; x < SizeXz; x++)
        for (int z = 0; z < SizeXz; z++)
        {
            bool skyOpen = true;
            for (int y = Height - 1; y >= 0; y--)
            {
                int index = Index(x, y, z);
                if (skyOpen && IsLightTransparent(blocks[index]))
                {
                    sunlight[index] = 15;
                    directMask[index >> 3] |= (byte)(1 << (index & 7));
                    directIndices.Add(index);
                }
                else skyOpen = false;
            }
        }
        verticalTimer.Stop();

        var bfsTimer = Stopwatch.StartNew();
        var queue = new List<int>();
        int seedCount = 0, queuePushes = 0, legacySeedCount = 0;
        int duplicateRejections = 0, neighborOperations = 0;
        foreach (int directIndex in directIndices)
        {
            int x = directIndex % SizeXz;
            int yz = directIndex / SizeXz;
            int z = yz % SizeXz;
            bool legacySourceCanSeed = false;
            for (int direction = 0; direction < 4; direction++)
            {
                int neighbor = direction switch
                {
                    0 when x > 0 => directIndex - 1,
                    1 when x + 1 < SizeXz => directIndex + 1,
                    2 when z > 0 => directIndex - SizeXz,
                    3 when z + 1 < SizeXz => directIndex + SizeXz,
                    _ => -1,
                };
                if (neighbor < 0) continue;
                neighborOperations++;
                if ((directMask[neighbor >> 3] & (1 << (neighbor & 7))) != 0) continue;
                if (!IsLightTransparent(blocks[neighbor])) continue;
                legacySourceCanSeed = true;
                if (sunlight[neighbor] >= 14) { duplicateRejections++; continue; }
                sunlight[neighbor] = 14;
                queue.Add(neighbor); seedCount++; queuePushes++;
            }
            if (legacySourceCanSeed) legacySeedCount++;
        }

        int queueIndex = 0;
        while (queueIndex < queue.Count)
        {
            int index = queue[queueIndex++];
            int level = sunlight[index];
            if (level <= 1) continue;
            int x = index % SizeXz;
            int yz = index / SizeXz;
            int z = yz % SizeXz;
            int y = yz / SizeXz;
            int desired = level - 1;
            for (int direction = 0; direction < 6; direction++)
            {
                int neighbor = direction switch
                {
                    0 when x > 0 => index - 1,
                    1 when x + 1 < SizeXz => index + 1,
                    2 when z > 0 => index - SizeXz,
                    3 when z + 1 < SizeXz => index + SizeXz,
                    4 when y > 0 => index - SizeXz * SizeXz,
                    5 when y + 1 < Height => index + SizeXz * SizeXz,
                    _ => -1,
                };
                if (neighbor < 0) continue;
                neighborOperations++;
                if (!IsLightTransparent(blocks[neighbor])) continue;
                if (desired <= sunlight[neighbor]) { duplicateRejections++; continue; }
                sunlight[neighbor] = (byte)desired;
                queue.Add(neighbor); queuePushes++;
            }
        }
        bfsTimer.Stop();
        return new SunlightProfile(ToUsec(verticalTimer), ToUsec(bfsTimer), directIndices.Count,
            seedCount, legacySeedCount, queueIndex, queuePushes, duplicateRejections, neighborOperations);
    }

    private static bool IsLightTransparent(int block) => block == Air || block == Torch;
    private static int Index(int x, int y, int z) => (y * SizeXz + z) * SizeXz + x;
    private static long ToUsec(Stopwatch timer) => (long)(timer.Elapsed.TotalMilliseconds * 1000.0);

    private static void BuildRelevantIndices(int[] blocks, out int[] special, out int[] emissive)
    {
        var specialList = new List<int>();
        var emissiveList = new List<int>();
        for (int i = 0; i < blocks.Length; i++)
        {
            if (blocks[i] != Torch) continue;
            specialList.Add(i);
            emissiveList.Add(i);
        }
        special = specialList.ToArray();
        emissive = emissiveList.ToArray();
    }

    private static GodotObject CreateChunkData(int[] blocks, byte[] sunlight, byte[] directMask,
        int[] specialIndices, int[] emissiveIndices)
    {
        var outer = new Godot.Collections.Array();
        for (int x = 0; x < SizeXz; x++)
        {
            var column = new Godot.Collections.Array();
            for (int y = 0; y < Height; y++)
            {
                var row = new Godot.Collections.Array();
                for (int z = 0; z < SizeXz; z++) row.Add(blocks[Index(x, y, z)]);
                column.Add(row);
            }
            outer.Add(column);
        }
        GodotObject data = ChunkDataScript.New(false).AsGodotObject();
        data.Set("blocks", outer);
        data.Set("block_light", new byte[Volume]);
        data.Set("sun_light", sunlight);
        data.Set("direct_sun_mask", directMask);
        data.Set("special_block_indices", specialIndices);
        data.Set("emissive_block_indices", emissiveIndices);
        return data;
    }

    private readonly record struct SunlightProfile(long VerticalUsec, long BfsUsec,
        int DirectVoxels, int SeedCount, int LegacySeedCount, int ProcessedVoxels,
        int QueuePushes, int DuplicateRejections, int NeighborOperations);
}
