const torrentSearchApi = require('torrent-search-api');
const WebTorrent = import('webtorrent');
const Castnow = require('castnow');
const inquirer = import('inquirer');

// Configure torrent-search-api to search for 1080p h264 torrents
torrentSearchApi.enableProvider('ThePirateBay');
torrentSearchApi.enableProvider('1337x');
torrentSearchApi.enableProvider('Torrentz2');
torrentSearchApi.enableProvider('Rarbg');
torrentSearchApi.enableProvider('EZTV');
torrentSearchApi.enableProvider('Yts');

const searchOptions = {
  category: 'TV',
  quality: '1080p',
  language: 'en',
  limit: '5',
  seeders: '10',
};

const client = new WebTorrent();
const castnow = new Castnow({ player: 'chromecast' });

async function searchAndStream() {
  const { seriesName } = await inquirer.prompt([
    {
      name: 'seriesName',
      message: 'Enter the name of the TV series:',
      type: 'input',
    },
  ]);

  const episodes = await torrentSearchApi.search(seriesName, '1080p', searchOptions);
  if (episodes.length === 0) {
    console.log('No 1080p h264 torrents found for this TV series.');
    return;
  }

  const latestEpisode = episodes[0];
  console.log(`Streaming ${latestEpisode.title}...`);

  client.add(latestEpisode.magnet, (torrent) => {
    const streamUrl = `http://localhost:${torrent.port}/${torrent.files[0].path}`;

    castnow.play(streamUrl, { address: '192.168.0.114' }, () => {
      console.log(`Finished streaming ${latestEpisode.title}.`);
    });
  });
}

searchAndStream();

