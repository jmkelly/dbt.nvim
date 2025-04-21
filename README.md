# dbt.nvim

A lightweight Neovim plugin to streamline .NET development workflows. Provides commands and keybindings to quickly build, restore, and test your .NET projects, with a floating terminal UI. Stands for [D]otnet [Build] and [T]est.

---

## ✨ Features

- Run `dotnet build` without restoring
- Run `dotnet restore`
- Run nearest test with `dotnet test` (without restore)
- Run nearest test with `dotnet build` (with restore)
- Configurable floating terminal layout
- Optional, user-configurable keybindings

---

## ⚡ Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jmkelly/dbt.nvim",
  config = function()
    require("dbt").setup()
  end,
}
```
---

## 🔧 Configuration

You can pass a configuration table to setup() to override the default layout or keymaps, but this is _only_ if you don't want to use the defaults

```lua 
require("dbt").setup({
  width_ratio = 1.0,
  height_ratio = 0.25,
  row_ratio = 0.75,
  col_ratio = 0.0,
  border = "rounded",
  keymaps = {
    enable = true,
    mappings = {
      build = "<leader>db",
      test_nearest = "<leader>dt",
    },
  },
})
```

---

## Disable Keymaps

Don't want plugin-defined keybindings? Just set enable = false:

```lua
require("dbt").setup({
  keymaps = {
    enable = false,
  }
})
```

---

## 🧪 Available Commands


Command | Description
:DotnetBuild | Run dotnet build without restore
:DotnetBuildAndRestore | Run dotnet build
:DotnetRestore | Run dotnet restore
:DotnetTestNearest | Run the nearest test method with dotnet test

---

## 🎯 Default Keymaps

Keybinding	Action
<leader>db	Build project (no restore)
<leader>dt	Test nearest method (no restore)

    💡 Keymaps are fully configurable via setup().

---

## 🧱 Requirements

    .NET SDK installed and available on your system

    Neovim 0.8+

---

## 📃 License

MIT
