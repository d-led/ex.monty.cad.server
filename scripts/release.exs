# The version of this application, bumped in one place and written into
# everything that carries it.
#
#   elixir scripts/release.exs bump patch    # 0.1.0 -> 0.1.1
#   elixir scripts/release.exs bump minor
#   elixir scripts/release.exs bump major
#   elixir scripts/release.exs check         # exit 1 when they disagree
#
# This repository is an application, not a Hex package: nothing is published from
# it, but the archive a deployment runs is cut from a tag, and a tag that names a
# version the files do not agree with is a release nobody can say the version of.
#
# `VERSION` is the source: a `mix.exs` is read only to check that nothing
# drifted. `check` runs in CI and before a tag.
#
# Tagging is a separate step (`scripts/tag_and_push_version.sh`):
# `.github/workflows/release.yml` builds the archive from the tag, and only after
# the commit's CI is green.
defmodule Release do
  @version_file "VERSION"

  @mix_files ["mix.exs"]

  def main(["bump", kind]) do
    current = current_version()
    next = bump(kind, current)

    File.write!(@version_file, next <> "\n")
    Enum.each(@mix_files, &rewrite!(&1, next))

    IO.puts("#{current} -> #{next}")
    IO.puts("Updated #{@version_file}, #{length(@mix_files)} mix.exs file(s)")

    # The bump is only done when the tree agrees with itself: a file the pattern
    # did not reach would leave the same drift the bump exists to prevent.
    main(["check"])

    IO.puts("\nNext: review the diff, commit, push, wait for CI to be green, then")
    IO.puts("./scripts/tag_and_push_version.sh")
  end

  def main(["check"]) do
    versions = [{"VERSION", current_version()} | Enum.map(@mix_files, &{&1, mix_version(&1)})]

    case Enum.uniq_by(versions, &elem(&1, 1)) do
      [_one] ->
        IO.puts("Everything is at #{current_version()}")

      _disagreement ->
        Enum.each(versions, fn {name, version} -> IO.puts("  #{name}: #{version}") end)
        Mix.raise("Versions disagree; run `elixir scripts/release.exs bump patch`")
    end
  end

  def main(_) do
    Mix.raise("Usage: elixir scripts/release.exs bump {major|minor|patch} | check")
  end

  defp bump("major", version), do: version |> parts() |> then(fn [m, _, _] -> "#{m + 1}.0.0" end)

  defp bump("minor", version),
    do: version |> parts() |> then(fn [m, n, _] -> "#{m}.#{n + 1}.0" end)

  defp bump("patch", version),
    do: version |> parts() |> then(fn [m, n, p] -> "#{m}.#{n}.#{p + 1}" end)

  defp bump(kind, _version),
    do: Mix.raise("Unknown bump #{inspect(kind)}; use major, minor or patch")

  defp parts(version) do
    case String.split(version, ".") do
      [major, minor, patch] ->
        [String.to_integer(major), String.to_integer(minor), String.to_integer(patch)]

      _not_a_release ->
        Mix.raise("Cannot parse version #{version}")
    end
  end

  defp current_version do
    @version_file |> File.read!() |> String.trim()
  end

  defp mix_version(path) do
    case Regex.run(~r/@version "([^"]+)"/, File.read!(path)) do
      [_, version] -> version
      nil -> Mix.raise("No @version in #{path}")
    end
  end

  # What a file states, or the same contents back when it already states the
  # version being written. A file with no `@version` at all is a broken file and
  # says so: that is the one case where "nothing to change" means the wrong
  # thing.
  defp rewrite!(path, version) do
    contents = File.read!(path)

    unless Regex.match?(~r/@version "[^"]+"/, contents) do
      Mix.raise("No @version in #{path}")
    end

    next = Regex.replace(~r/@version "[^"]+"/, contents, ~s(@version "#{version}"))
    if next != contents, do: File.write!(path, next)
  end
end

Release.main(System.argv())
