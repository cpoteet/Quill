'use strict'

// Maps Tiptap node names to Gutenberg block names, the shape that governs how
// the node projects to and from the block tree, and how block attributes are
// derived from the rendered element.

const BLOCK_DESCRIPTORS = {
  paragraph:   { blockName: 'core/paragraph',    shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  heading:     { blockName: 'core/heading',      shape: 'text',      childBlockName: null,             attrsFrom: el => ({ level: parseInt(el.tagName.slice(1), 10) }) },
  bulletList:  { blockName: 'core/list',         shape: 'container', childBlockName: 'core/list-item', attrsFrom: () => ({}) },
  orderedList: { blockName: 'core/list',         shape: 'container', childBlockName: 'core/list-item', attrsFrom: () => ({ ordered: true }) },
  listItem:    { blockName: 'core/list-item',    shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  blockquote:  { blockName: 'core/quote',        shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  codeBlock:   { blockName: 'core/code',         shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  horizontalRule: { blockName: 'core/separator', shape: 'leaf',      childBlockName: null,             attrsFrom: () => ({}) },
  table:       { blockName: 'core/table',        shape: 'media',     childBlockName: null,             attrsFrom: () => ({}) },
  footnotesList: { blockName: 'core/footnotes',  shape: 'media',     childBlockName: null,             attrsFrom: () => ({}) },
  columnsBlock: { blockName: 'core/columns', shape: 'container', childBlockName: 'core/column', attrsFrom: () => ({}) },
  columnBlock:  { blockName: 'core/column',  shape: 'container', childBlockName: null,          attrsFrom: () => ({}) },
  detailsBlock: { blockName: 'core/details', shape: 'container', childBlockName: null, attrsFrom: el => (el.hasAttribute('open') ? { showContent: true } : {}) },
  buttonsBlock: { blockName: 'core/buttons', shape: 'container', childBlockName: 'core/button', attrsFrom: () => ({}) },
  buttonBlock:  { blockName: 'core/button',  shape: 'text',      childBlockName: null,          attrsFrom: () => ({}) },
  accordionBlock:   { blockName: 'core/accordion',         shape: 'container', childBlockName: 'core/accordion-item', attrsFrom: el => (el.hasAttribute('data-autoclose') ? { autoclose: true } : {}) },
  accordionItem:    { blockName: 'core/accordion-item',    shape: 'container', childBlockName: null,                  attrsFrom: () => ({}) },
  accordionHeading: { blockName: 'core/accordion-heading', shape: 'text',      childBlockName: null,                  attrsFrom: () => ({}) },
  accordionPanel:   { blockName: 'core/accordion-panel',   shape: 'container', childBlockName: null,                  attrsFrom: () => ({}) },
}

function descriptorFor(nodeName) {
  return BLOCK_DESCRIPTORS[nodeName] || null
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { BLOCK_DESCRIPTORS, descriptorFor }
}
