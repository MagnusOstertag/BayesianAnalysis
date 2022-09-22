import os
import requests
from tqdm import tqdm
import time
import json
import pandas as pd
from string import ascii_lowercase
import logging
import asyncio
import aiohttp
import datetime
import argparse

logging.basicConfig(level="INFO")


def load_credentials(path):
    """
    Loading credentials from path
    """
    with open(path) as f:
        data = json.load(f)
    return data


def get_auth_data(credentials):
    """Posts the authentification request and returns the response data

    Args:
        credentials (json): from load_credentials()

    Returns:
        json: response of the request
    """

    AUTH_URL = "https://accounts.spotify.com/api/token"

    # POST
    auth_response = requests.post(
        AUTH_URL,
        {
            "grant_type": "client_credentials",
            "client_id": credentials["client_id"],
            "client_secret": credentials["client_secret"],
        },
    )

    # convert the response to JSON
    auth_response_data = auth_response.json()

    return auth_response_data


def get_spotify_headers(credentials):
    """
    Necessay header to perform as http request
    """

    auth_data = get_auth_data(credentials)

    # create the header for each request
    headers = {
        "Authorization": "Bearer {token}".format(token=auth_data["access_token"]),
    }
    return headers


async def get_track_metadata(
    tracks: pd.DataFrame,
    credentials: dict,
    session: aiohttp.ClientSession,
    filename: str,
):
    """
    Get the metadata of artits
    """

    headers = get_spotify_headers(credentials)

    track_url_template = "https://api.spotify.com/v1/tracks?ids={}"

    urls = []
    df = pd.DataFrame()
    errors = []

    track_ids = tracks["track_id"].tolist()

    batches = get_batches(track_ids, 50)

    for batch in batches:
        urls.append(track_url_template.format(",".join(batch)))

    batches = get_batches(urls, 50)

    for batch in tqdm(batches):
        for coro in asyncio.as_completed(
            [fetch_page(page, session, headers) for page in batch]
        ):

            res, url_page = await coro

            if res:
                rows = []

                # parse the metadata
                tracks_metadata = res["tracks"]

                for f in tracks_metadata:
                    # currently we only parse id, popularity and total followers
                    row = {}

                    row["track_id"] = f["id"]
                    row["release_date"] = f["album"]["release_date"]

                    rows.append(row)

                update = pd.DataFrame(rows)
                df = pd.concat([df, update], axis=0)

            else:
                errors.append(url_page)

        time.sleep(5)

    df.to_csv(filename, index=False)

    return df


async def get_artist_metadata(
    tracks: pd.DataFrame,
    credentials: dict,
    session: aiohttp.ClientSession,
    filename: str,
):
    """
    Get the metadata of artits
    """

    headers = get_spotify_headers(credentials)

    track_url_template = "https://api.spotify.com/v1/artists?ids={}"

    urls = []
    df = pd.DataFrame()
    errors = []

    artists = tracks["artist_id"].tolist()

    batches = get_batches(artists, 50)

    for batch in batches:
        urls.append(track_url_template.format(",".join(batch)))

    batches = get_batches(urls, 50)

    for batch in tqdm(batches):
        for coro in asyncio.as_completed(
            [fetch_page(page, session, headers) for page in batch]
        ):

            res, url_page = await coro

            if res:
                rows = []

                # parse the metadata
                artists_features = res["artists"]

                for f in artists_features:
                    # currently we only parse id, popularity and total followers
                    row = {}
                    row["id"] = f["id"]
                    row["popularity"] = f["popularity"]
                    row["artist_total_followers"] = f["followers"]["total"]

                    rows.append(row)

                update = pd.DataFrame(rows)
                df = pd.concat([df, update], axis=0)

            else:
                errors.append(url_page)

        time.sleep(5)

    df.to_csv(filename, index=False)

    return df


async def get_track_audio_features(
    tracks: pd.DataFrame,
    credentials: dict,
    session: aiohttp.ClientSession,
    filename: str,
):
    """
    Get the metadata of songs
    """

    headers = get_spotify_headers(credentials)

    track_url_template = "https://api.spotify.com/v1/audio-features?ids={}"

    urls = []
    df = pd.DataFrame()
    errors = []

    tracks = tracks["track_id"].tolist()

    batches = get_batches(tracks, 100)

    for batch in batches:
        urls.append(track_url_template.format(",".join(batch)))

    batches = get_batches(urls, 50)

    for batch in tqdm(batches):
        for coro in asyncio.as_completed(
            [fetch_page(page, session, headers) for page in batch]
        ):

            res, url_page = await coro

            if res:
                rows = []

                # parse the metadata
                audio_features = res["audio_features"]

                for f in audio_features:
                    rows.append(f)

                update = pd.DataFrame(rows)
                df = pd.concat([df, update], axis=0)

            else:
                errors.append(url_page)

        time.sleep(5)

    df.to_csv(filename, index=False)

    return df


def update_dataframe(data: dict, df: pd.DataFrame):
    """
    Update dataframe with a dict object
    """
    update = []

    for track in data["tracks"]["items"]:

        row = {
            "name": track["name"],
            "track_id": track["id"],
            # parse the first artist
            "artist": track["artists"][0]["name"],
            # parse also the id of the artist
            "artist_id": track["artists"][0]["id"],
            # parse the popularity
            "track_popularity": track["popularity"],
        }
        update.append(row)

    update = pd.DataFrame(update)

    df = pd.concat([df, update], axis=0)

    return df


def get_url_pages(base_url, total_limit):
    """
    Get pages for async
    """

    pages = []

    # starting value for offset
    offset = 50

    while offset < total_limit:
        pages.append(base_url + f"&offset={offset}")
        offset += 50

    return pages


async def fetch_page(url_page, session, headers):
    """
    Async fetch of spotify page
    """

    async with session.get(url_page, headers=headers) as response:

        if response.status == 200:
            data = await response.read()
            return (json.loads(data), url_page)
        else:
            logging.error(f"invalid request with {response.status} for {url_page}")
            return (None, url_page)


def get_batches(items, batch_size):
    """
    Create batches of `batch_size` from a items list
    """
    batches = []
    counter = 0

    while counter * batch_size < len(items):
        batches.append(items[counter * batch_size : (counter + 1) * batch_size])
        counter += 1

    return batches


async def naive_search_tracks(credentials, session, filename, genre="indie", year=2022):
    """
    Perform an naive search of all possible tracks by searching them alphabetically (aaa, aab, ...)
    This is done to avoid the imposed limit of 1000 items per api page result.
    """

    headers = get_spotify_headers(credentials)
    base_url = (
        f"https://api.spotify.com/v1/search?q=genre:{genre}+year:{year}+"
        + "track:{}*&type=track&limit=50"
    )
    base_urls = []
    second_batch = []
    json_parser_errors = []

    df = pd.DataFrame()

    for c1 in ascii_lowercase:
        for c2 in ascii_lowercase:
            for c3 in ascii_lowercase:
                base_urls.append(base_url.format(c1 + c2 + c3))

    logging.info(f"First Batch: Performing {len(base_urls)} requests ...")

    batches = get_batches(base_urls, 100)

    # perform the first batch
    for batch in tqdm(batches):
        for coro in asyncio.as_completed(
            [fetch_page(page, session, headers) for page in batch]
        ):

            res, url_page = await coro

            if res:
                df = update_dataframe(res, df)

                if res["tracks"]["total"] > 50:
                    second_batch.append((url_page, res["tracks"]["total"]))
            else:
                json_parser_errors.append(url_page)

        # perform sleep times in order to avoid api overcrowding
        time.sleep(10)

    print(f"Unsuccseful parsing {len(json_parser_errors)} / {len(base_urls)}")

    # get the urls with more than 50 res per page
    base_urls = []
    json_parser_errors = []

    for url_page, total_limit in second_batch:
        pages = get_url_pages(url_page, total_limit)
        for p in pages:
            base_urls.append(p)

    logging.info(f"Second Batch: Performing {len(base_urls)} requests ...")

    # perform sleep times in order to avoid api overcrowding
    time.sleep(30)

    batches = get_batches(base_urls, 30)

    # perform the second batch
    for batch in tqdm(batches):
        for coro in asyncio.as_completed(
            [fetch_page(page, session, headers) for page in batch]
        ):
            res, url_page = await coro

            if res is not None and "tracks" in res:
                df = update_dataframe(res, df)
            else:
                json_parser_errors.append(res)

        time.sleep(15)

    logging.info(f"Unsuccseful parsing: {len(json_parser_errors)}/{len(base_urls)}")

    df.to_csv(filename, index=False)


async def full_download(
    folder,
    credentials,
    genre,
    year,
):
    """
    It performs a full download of tracks with the respective genre and year.
    """

    filename = os.path.join(folder, "track.csv")

    # # download the indie songs (name + id)
    async with aiohttp.ClientSession() as session:
        await naive_search_tracks(credentials, session, filename, genre, year)

    # gather metadata
    tracks = pd.read_csv(filename)

    # preprocessing steps
    tracks = tracks.drop_duplicates(subset=["name", "artist"])

    logging.info(f"Searching for audio features for {len(tracks)}")

    # Create special filenames for artist metadata + track metadata
    f_artist_metadata = os.path.join(folder, f"artist_metadata.csv")
    f_track_metadata = os.path.join(folder, f"track_metadata.csv")
    f_track_features = os.path.join(folder, f"track_features.csv")

    async with aiohttp.ClientSession() as session:
        await get_artist_metadata(tracks, credentials, session, f_artist_metadata)
        await get_track_metadata(tracks, credentials, session, f_track_metadata)
        await get_track_audio_features(tracks, credentials, session, f_track_features)

    # loading all artist metadata
    artist_metadata = pd.read_csv(f_artist_metadata)
    artist_metadata = artist_metadata.rename(
        columns={"id": "artist_id", "popularity": "artist_popularity"}
    )
    artist_metadata = artist_metadata.drop_duplicates(subset=["artist_id"])

    # loading all track metadata
    track_metadata = pd.read_csv(f_track_metadata)

    # loading all track audio features
    track_features = pd.read_csv(f_track_features)
    track_features = track_features.rename(columns={"id": "track_id"})

    tracks = tracks.merge(artist_metadata, on=["artist_id"], how="inner")
    tracks = tracks.merge(track_metadata, on=["track_id"], how="inner")
    tracks = tracks.merge(track_features, on=["track_id"], how="inner")

    tracks.to_csv(filename, index=False)


async def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--genre", type=str, required=True)
    parser.add_argument("--year", type=int, required=True)

    args = parser.parse_args()

    date_today = datetime.date.today()
    date_today = str(date_today).replace("-", "_")

    folder = str(date_today)
    os.mkdir(folder)

    year = args.year
    genre = args.genre

    logging.info(
        f"Downloading tracks + metadata for tracks with genre {genre} and year {year}"
    )

    credentials = load_credentials("credentials.json")

    await full_download(
        folder,
        credentials,
        genre,
        year,
    )


if __name__ == "__main__":
    asyncio.run(main())
