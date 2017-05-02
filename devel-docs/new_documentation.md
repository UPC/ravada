Normally the documentation files are stored in /docs and /devel-docs directories.

When you create a new page keep in mind don't leave blanks in the filename.

The file name is used to generate a "title page".

## Static content generated from md files

These files are used to autogenerate html page accesibles from [Ravada's web](https://upc.github.io/ravada/index.html). [Templer](https://github.com/skx/templer) is used to do this.

### Templerfy

For do that you need to following steps: 

(Requirements: [Templer](https://github.com/skx/templer) installed in your computer. See "Installation" section.

- change to gh-pages branch
- cd templer
- ./templerfy.sh
- If all is correct, upload changes to repository.
