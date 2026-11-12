defmodule Mix.Tasks.ExMontyCadServer.ToolsDoc do
  @shortdoc "Writes docs/tools.md from the catalogue the server answers with"

  @moduledoc """
  Writes the tool reference, from the catalogue rather than from memory.

      mix ex_monty_cad_server.tools_doc           # write docs/tools.md
      mix ex_monty_cad_server.tools_doc --check   # fail if it is out of date

  `--check` is what CI runs: a tool whose description was changed in the
  catalogue and not in the page is a page that lies about the server, and this is
  the only way to notice before a model reads it.
  """

  use Mix.Task

  @path "docs/tools.md"

  @impl true
  def run(arguments) do
    Mix.Task.run("compile", [])

    rendered = ExMontyCadServer.Docs.ToolReference.render()
    committed = File.read(@path)

    if "--check" in arguments do
      check(rendered, committed)
    else
      File.mkdir_p!(Path.dirname(@path))
      File.write!(@path, rendered)
      Mix.shell().info("wrote #{@path}")
    end
  end

  defp check(rendered, committed) do
    case committed do
      {:ok, ^rendered} ->
        Mix.shell().info("#{@path} matches the catalogue")

      {:ok, _stale} ->
        Mix.raise("#{@path} is out of date; run `mix ex_monty_cad_server.tools_doc`")

      {:error, reason} ->
        Mix.raise(
          "#{@path} cannot be read (#{:file.format_error(reason)}); " <>
            "run `mix ex_monty_cad_server.tools_doc`"
        )
    end
  end
end
