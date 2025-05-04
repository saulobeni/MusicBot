defmodule MusicBot.Commands do
  @moduledoc """
  Módulo contendo todos os comandos do bot de música, cada um consumindo uma API diferente.
  """

  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  require Logger

  @lyrics_api "https://api.lyrics.ovh/v1/"
  @artist_api "https://www.theaudiodb.com/api/v1/json/2/search.php?s="
  @recommend_api "https://api.deezer.com/radio/%s"
  @playlist_api "https://api.spotify.com/v1/search"
  @song_api "https://api.songkick.com/api/3.0/search/artists.json"
  @genre_api "https://binaryjazz.us/wp-json/genrenator/v1/genre/"
  @cover_api "https://itunes.apple.com/search"

  @doc """
  Busca letras de música usando a API Lyrics.ovh
  """
  def get_lyrics(msg, [artist, song]) do
    artist = URI.encode(artist)
    song = URI.encode(song)

    case HTTPoison.get("#{@lyrics_api}#{artist}/#{song}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        lyrics = Jason.decode!(body)["lyrics"]
        Api.Message.create(msg.channel_id, "**#{song} - #{artist}**\n\n#{String.slice(lyrics, 0..1500)}...")

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Api.Message.create(msg.channel_id, "Letra não encontrada para #{song} de #{artist}")

      {:error, error} ->
        Logger.error("Lyrics API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar letra")
    end
  end

  @doc """
  Obtém informações sobre um artista usando TheAudioDB API
  """
  def get_artist_info(msg, [artist]) do
    artist = URI.encode(artist)

    case HTTPoison.get("#{@artist_api}#{artist}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)["artists"] |> List.first()

        embed = %Embed{
          title: data["strArtist"],
          description: data["strBiographyEN"] |> String.slice(0..500) |> String.trim() |> Kernel.<>("..."),
          thumbnail: %Embed.Thumbnail{url: data["strArtistThumb"]},
          fields: [
            %Embed.Field{name: "Gênero", value: data["strGenre"], inline: true},
            %Embed.Field{name: "País", value: data["strCountry"], inline: true},
            %Embed.Field{name: "Ano de Formação", value: data["intFormedYear"], inline: true}
          ]
        }

        Api.Message.create(msg.channel_id, embed: embed)

      {:error, error} ->
        Logger.error("Artist API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar informações do artista")
    end
  end

  @doc """
  Obtém recomendações de música baseadas em um artista/gênero usando Deezer API
  """
  def get_recommendations(msg, [query]) do
    query = URI.encode(query)

    case HTTPoison.get("#{@recommend_api}#{query}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)

        tracks = Enum.map(data["data"], fn track ->
          "#{track["title"]} - #{track["artist"]["name"]}"
        end)

        Api.Message.create(msg.channel_id, "**Recomendações para #{query}**:\n\n#{Enum.join(tracks, "\n")}")

      {:error, error} ->
        Logger.error("Recommendation API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar recomendações")
    end
  end

  @doc """
  Gera uma playlist baseada em uma consulta usando Spotify API
  """
  def generate_playlist(msg, [query]) do
    query = URI.encode(query)

    case HTTPoison.get("#{@playlist_api}?q=#{query}&type=playlist&limit=5") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        playlists = Jason.decode!(body)["playlists"]["items"]

        response = Enum.map(playlists, fn playlist ->
          "[#{playlist["name"]}](#{playlist["external_urls"]["spotify"]}) - #{playlist["tracks"]["total"]} músicas"
        end)

        Api.Message.create(msg.channel_id, "**Playlists encontradas para #{query}**:\n\n#{Enum.join(response, "\n\n")}")

      {:error, error} ->
        Logger.error("Playlist API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar playlists")
    end
  end

  @doc """
  Obtém informações sobre uma música usando Songkick API
  """
  def get_song_info(msg, [song]) do
    song = URI.encode(song)

    case HTTPoison.get("#{@song_api}?query=#{song}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)["resultsPage"]["results"]["artist"] |> List.first()

        embed = %Embed{
          title: data["displayName"],
          url: data["uri"],
          fields: [
            %Embed.Field{name: "Seguidores", value: data["stats"]["followers"], inline: true},
            %Embed.Field{name: "Eventos", value: data["stats"]["eventCount"], inline: true}
          ]
        }

        Api.Message.create(msg.channel_id, embed: embed)

      {:error, error} ->
        Logger.error("Song API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar informações da música")
    end
  end

  @doc """
  Gera um gênero musical aleatório usando Genrenator API
  """
  def get_genre_info(msg, _args) do
    case HTTPoison.get("#{@genre_api}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        genre = Jason.decode!(body)
        Api.Message.create(msg.channel_id, "**Gênero musical aleatório**: #{genre}")

      {:error, error} ->
        Logger.error("Genre API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao gerar gênero musical")
    end
  end

  @doc """
  Obtém a capa de um álbum usando iTunes API
  """
  def get_album_cover(msg, [artist, album]) do
    artist = URI.encode(artist)
    album = URI.encode(album)

    case HTTPoison.get("#{@cover_api}?term=#{artist}+#{album}&entity=album&limit=1") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)["results"] |> List.first()

        if data do
          embed = %Embed{
            title: "#{data["collectionName"]} - #{data["artistName"]}",
            image: %Embed.Image{url: data["artworkUrl100"] |> String.replace("100x100bb.jpg", "500x500bb.jpg")}
          }

          Api.Message.create(msg.channel_id, embed: embed)
        else
          Api.Message.create(msg.channel_id, "Álbum não encontrado")
        end

      {:error, error} ->
        Logger.error("Cover API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar capa do álbum")
    end
  end
end
