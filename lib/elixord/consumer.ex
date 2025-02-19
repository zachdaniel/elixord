defmodule Elixord.Consumer do
  use Nostrum.Consumer
  @ash_guild 711_271_361_523_351_632

  # @commands [
  #   GG.Tricks.Backflip,
  #   GG.Tricks.Apple
  # ]
  #
  # @listeners [GG.Actors.Apollonius, GG.Actors.Sevro, GG.Actors.Ephraim, GG.Actors.Mustang]
  #
  # require Logger
  #
  def handle_event({:READY, _msg, _ws_state}) do
    Nostrum.Api.ApplicationCommand.create_guild_command(@ash_guild, %{
      name: "hexdocs",
      description: "Search hexdocs",
      options: [
        %{
          name: "packages",
          type: 3,
          required: true,
          description: "A comma separated list of packages to search"
        },
        %{name: "query", type: 3, required: true, description: "What to search for on hexdocs"}
      ]
    })

    IO.puts("READY")
  end

  def handle_event(
        {:INTERACTION_CREATE,
         %Nostrum.Struct.Interaction{data: %{name: "hexdocs", options: options}} = interaction,
         _ws_state}
      ) do
    packages =
      Enum.find(options, &(&1.name == "packages")).value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(fn package ->
        case String.split(package, "-") do
          [package] ->
            case Req.get("https://hex.pm/api/packages/#{package}",
                   headers: [{"User-Agent", "igniter-installer"}]
                 ) do
              {:ok, %{body: %{"releases" => releases} = body}} ->
                case first_non_rc_version_or_first_version(releases, body) do
                  %{"version" => version} ->
                    ["#{package}-#{version}"]

                  _ ->
                    []
                end
            end

          _ ->
            [package]
        end
      end)

    query = Enum.find(options, &(&1.name == "query")).value

    params = %{
      q: query,
      filter_by: "package:=[#{Enum.join(packages, ",")}]",
      query_by: "title,doc"
    }

    Req.get!("https://search.hexdocs.pm/?#{URI.encode_query(params)}",
      headers: [{"User-Agent", "elixord"}]
    )
    |> Map.get(:body)
    |> Map.get("hits")
    |> Enum.map_join("\n", fn hit ->
      url = Enum.join(String.split(hit["document"]["package"], "-"), "/")

      "- [#{hit["document"]["type"]} | #{hit["document"]["title"]}](https://hexdocs.pm/#{url}/#{hit["document"]["ref"]})"
    end)
    |> then(fn result ->
      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: %{
          content: "Searched #{Enum.join(packages, ", ")} for #{query}:\n" <> result
        }
      })
    end)
  end

  def handle_event(other) do
    IO.inspect(other, label: "no known event")
    :ok
  end

  defp split_into_chunks(strings, max_length) do
    strings
    |> Enum.reduce({[], ""}, fn string, {chunks, current_chunk} ->
      new_chunk = current_chunk <> "\n" <> string

      if String.length(new_chunk) > max_length and current_chunk != "" do
        {[current_chunk | chunks], string}
      else
        {chunks, new_chunk}
      end
    end)
    |> then(fn {chunks, last_chunk} ->
      if last_chunk != "" do
        [last_chunk | chunks]
      else
        chunks
      end
    end)
    |> Enum.reverse()
  end

  defp first_non_rc_version_or_first_version(releases, body) do
    releases = Enum.reject(releases, &body["retirements"][&1["version"]])

    Enum.find(releases, Enum.at(releases, 0), fn release ->
      !rc?(release["version"])
    end)
  end

  # This just actually checks if there is any pre-release metadata
  defp rc?(version) do
    version
    |> Version.parse!()
    |> Map.get(:pre)
    |> Enum.any?()
  end

  # defp highlights(hit) do
  #   highlights = hit["highlights"] || hit["highlight"]
  #
  #   if highlights && !Enum.empty?(highlights) do
  #     do_highlights(highlights)
  #   else
  #     ""
  #   end
  # end
  #
  # defp do_highlights(highlights) do
  #   "\n" <>
  #     Enum.map_join(highlights, fn highlight ->
  #       "  " <>
  #         Enum.map_join(String.split(replace_marks(highlight["snippet"]), "\n"), "\n", &"  #{&1}")
  #     end)
  # end

  # defp replace_marks(snippet) do
  #   snippet
  #   |> String.replace("<mark>", "**")
  #   |> String.replace("</mark>", "**")
  # end
end
