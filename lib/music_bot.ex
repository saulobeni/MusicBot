defmodule MusicBot do
  use Nostrum.Consumer

  alias Nostrum.Api.Message
  alias MusicBot.Commands

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case String.starts_with?(msg.content, "!") do
      true -> process_command(msg)
      false -> :ignore
    end
  end

  defp process_command(msg) do
    command =
      msg.content
      |> String.slice(1..-1//1)
      |> String.split(" ")
      |> hd()

    args = String.split(msg.content, " ") |> tl()

    case command do
      "lyrics" ->
        Commands.get_lyrics(msg, args)

      "artist" ->
        Commands.get_artist_info(msg, args)

      "recommend" ->
        Commands.get_recommendations(msg, args)

      "playlist" ->
        Commands.generate_playlist(msg, args)

      "song" ->
        Commands.get_song_info(msg, args)

      "genre" ->
        Commands.get_genre_info(msg, args)

      "cover" ->
        Commands.get_album_cover(msg, args)

      "search" ->
        Commands.search_song(msg, args)

      _ ->
        Message.create(
          msg.channel_id,
          "Comando desconhecido. Comandos disponíveis: !lyrics, !artist, !recommend, !playlist, !song, !genre, !cover, !search"
        )
    end
  end
end
