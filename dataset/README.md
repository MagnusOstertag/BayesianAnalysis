# Spotify Dataset crawler

The python based crawler is used to collect data about artists and tracks from the Spotify api.

## How does it function?

- the first step in order to use the crawler is to create an API client(App) on the [Spotify website](https://developer.spotify.com/dashboard/applications).
  Using the _client id_ and the _client secret_ we can make a succesfull authentification with the Spotify api.

The next step is to perform a _naive download_ of the tracks using the follwoing api request `https://api.spotify.com/v1/search?q=genre:indie+year:2022+track:{}*&type=track&limit=50`.
By using an _alphabetical search_ (aaa, aab, ...) we manage to download all tracks. We need to perform this search because of the 1000 item search imposed by Spotify api.

Due to the fact that there is a risk of sending to many request per minute, we're gonna insert _sleep times_ in order to avoid an error when downloading all the tracks.
If spotify API has to many requests it will deliver the code (429).
