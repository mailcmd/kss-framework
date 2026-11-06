
// Event fired after KSS.init
window.addEventListener('kssready', function(e){
    console.log('kss-ready event triggered!', e);
});

// Main process
(async function(){
    await KSS.include('@mods/bigtable/index.js');
    KSS.init();
})();
