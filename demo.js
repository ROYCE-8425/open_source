const fs = require('fs');
const path = require('path');
const carbone = require('./lib/index.js');

// Dữ liệu mẫu truyền vào template
const data = [
  {
    movieName: 'The Matrix',
    actors: [
      { firstname: 'Keanu', lastname: 'Reeves' },
      { firstname: 'Laurence', lastname: 'Fishburne' },
      { firstname: 'Carrie-Anne', lastname: 'Moss' }
    ]
  },
  {
    movieName: 'Back To The Future',
    actors: [
      { firstname: 'Michael', lastname: 'J. Fox' },
      { firstname: 'Christopher', lastname: 'Lloyd' }
    ]
  }
];

const templatePath = path.join(__dirname, 'examples', 'movies.docx');
const outputPath = path.join(__dirname, 'movies_result.docx');

console.log('--- Đang render tài liệu mẫu với Carbone ---');
console.log('Template:', templatePath);

carbone.render(templatePath, data, function (err, result) {
  if (err) {
    console.error('Lỗi khi render:', err);
    return;
  }
  fs.writeFileSync(outputPath, result);
  console.log(' Render thành công!');
  console.log('File xuất ra tại:', outputPath);
});
