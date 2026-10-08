marked.use({extensions:[
{name:'blockMath',level:'block',start(src){const m=/\$\$|\\\[/.exec(src);return m?m.index:undefined;},tokenizer(src){const m=/^(?:\$\$\s*\n?([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\])(?:\s*\n|$)/.exec(src);if(m)return {type:'blockMath',raw:m[0],tex:m[1]||m[2]};},renderer(token){return mathMarkup(token.tex,true);}},
{name:'inlineMath',level:'inline',start(src){const m=/\$|\\\(/.exec(src);return m?m.index:undefined;},tokenizer(src){const m=/^(?:\$(?!\$)((?:\\.|[^$\n])+?)\$(?!\$)|\\\(([\s\S]+?)\\\))/.exec(src);if(m)return {type:'inlineMath',raw:m[0],tex:m[1]||m[2]};},renderer(token){return mathMarkup(token.tex,false);}}
]});
function mathMarkup(tex,display){const safe=tex.replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;');return '<'+(display?'div':'span')+' class="math-expression" data-display="'+display+'" data-tex="'+safe+'"></'+(display?'div':'span')+'>';}
function renderMarkdownMath(root){root.querySelectorAll('.math-expression').forEach(node=>{katex.render(node.dataset.tex,node,{displayMode:node.dataset.display==='true',throwOnError:false,trust:false,maxExpand:1000});});}
