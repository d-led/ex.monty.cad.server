defmodule ExMontyCadServer.Docs.ToolReferenceTest do
  @moduledoc """
  The page and the server cannot disagree: `docs/tools.md` is what the catalogue
  renders, and a description edited in one place and not the other fails here
  rather than in front of a model.
  """
  use ExUnit.Case, async: true

  alias ExMontyCadServer.Docs.ToolReference
  alias ExMontyCadServer.Mcp.Tools

  @path Path.expand("../../../docs/tools.md", __DIR__)

  test "the committed page is what the catalogue renders" do
    assert File.read!(@path) == ToolReference.render(),
           "docs/tools.md is out of date; run `mix ex_monty_cad_server.tools_doc`"
  end

  test "every tool the server answers is named in the page" do
    page = File.read!(@path)

    for name <- Tools.names() do
      assert page =~ "`#{name}`"
    end
  end

  test "every tool under an engine heading has that engine in its name" do
    page = File.read!(@path)

    # The headings are the engines in lookup order; a tool listed under one that
    # does not claim its name is a tool a reader will look for in the wrong place.
    for {engine, module} <- Tools.engines(),
        tool <- module.catalogue() do
      assert page =~ "`#{tool["name"]}`"
      assert Tools.engine(tool["name"]) == {engine, module}
    end
  end
end
