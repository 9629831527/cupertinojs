function test(a){
    if(a < 10){
        return test(a+1);
    }
    return a
}


function objcjs_main(a, b){
    NSLog("null %@ \n", test(0))
    NSLog("null %@ \n", test(11))
    return 1;
}
