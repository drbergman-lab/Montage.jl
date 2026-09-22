```@meta
CurrentModule = Montage
```

# [API reference](@id reference-page)

Every exported name, plus every method the package extensions add once their packages are
loaded. Internal helpers are documented under [Architecture](@ref architecture-page).

```@index
Pages = ["reference.md"]
```

## Composition types

```@autodocs
Modules = [Montage]
Filter = t -> t in (Montage.Panel, Montage.MontageSpec)
```

## The verbs

```@autodocs
Modules = [Montage]
Filter = t -> t in (Montage.montage, Montage.storyboard, Montage.tableau, Montage.record)
```

## PhysiCell output folders

Available with `using PhysiCellOutput` (or `using PhysiCellModelManager`, which depends on it).
See [PhysiCell simulations](@ref physicell-page).

```@autodocs
Modules = [Main.MontagePhysiCellOutputExt]
Filter = t -> t isa Function && nameof(t) in (:montage, :storyboard, :tableau, :record)
```

## PhysiCell simulations by id

Available with `using PhysiCellModelManager`.

```@autodocs
Modules = [Main.MontagePhysiCellModelManagerExt]
Filter = t -> t isa Function && nameof(t) in (:montage, :storyboard, :tableau, :record)
```

## Tableau

Available with `using CairoMakie`; the simulation methods also need a PhysiCell package.

```@autodocs
Modules = [Main.MontageCairoMakieExt, Main.MontageCairoMakiePhysiCellOutputExt, Main.MontageCairoMakiePCMMExt]
Filter = t -> t isa Function && nameof(t) in (:montage, :storyboard, :tableau, :record)
```
