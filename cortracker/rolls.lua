-- RollTracker Classic XI / Phoenix XI roll data


return {
    ['Corsair\'s Roll'] = {
        lucky=5, unlucky=9, desc='Experience / Capacity Points', percent=true, values={
            [0]={10,11,11,12,20,13,15,16,8,17,24},
        },
        bust=6,
    },

    ['Ninja Roll'] = {
        lucky=4, unlucky=8, desc='Evasion', values={
            [0]={4,6,8,25,10,12,14,2,17,20,30},
        },
        bust=8,
    },

    ['Hunter\'s Roll'] = {
        lucky=4, unlucky=8, desc='Accuracy', values={
            [0]={10,13,15,40,18,20,25,5,27,30,50},
        }, bust=5,
    },
    
    ['Chaos Roll'] = {
        lucky=4, unlucky=8, desc='Attack', percent=true, values={
            [0]={6.3,7.8,9.4,25,10.9,12.5,15.6,3.1,17.2,18.8,31.2},
        }, bust=10,
    },
    
    ['Magus\'s Roll'] = {
        lucky=2, unlucky=6, desc='Magic Defense Bonus', values={
            [0]={3,10,4,4,5,1,6,7,8,9,18},
        }, bust=5,
    },

    ['Healer\'s Roll'] = {
        lucky=3, unlucky=7, desc='MP Recovered while healing', values={
            [0]={2,3,10,4,4,5,1,6,7,7,12},
        }, bust=3,
    },
    
    ['Drachen Roll'] = {
        lucky=3, unlucky=7, desc='Pet: Magic Accuracy / Pet: Magic Attack', values={
            [0]={4,5,18,7,9,10,2,11,13,15,22},
        }, bust=8,
    },
    
    ['Choral Roll'] = {
        lucky=2, unlucky=6, desc='Spell Interruption Rate down', percent=true, values={
            [0]={4,17,5,6,7,2,8,10,11,12,21},
        }, bust=8,
    },
    
    ['Monk\'s Roll'] = {
        lucky=3, unlucky=7, desc='Subtle Blow', values={
            [0]={8,10,32,12,14,16,4,20,22,24,40},
        }, bust=11,
    },
    
    ['Beast Roll'] = {
        lucky=4, unlucky=8, desc='Pet: Attack', percent=true, values={
            [0]={5,6,7,19,8,9,12,2,13,14,23},
        }, bust=8,
    },

    ['Samurai Roll'] = {
        lucky=2, unlucky=6, desc='Store TP', values={
            [0]={8,32,10,12,14,4,16,20,22,24,40},
        }, bust=5,
    },

    ['Evoker\'s Roll'] = {
        lucky=5, unlucky=9, desc='Refresh', values={
            [0]={1,1,1,1,3,2,2,2,1,3,4},
        }, bust=nil,
    },
    
    ['Rogue\'s Roll'] = {
        lucky=5, unlucky=9, desc='Critical Hit Rate', percent=true, values={
            [0]={2,2,3,4,12,5,6,6,1,8,19},
        }, bust=6,
    },
    
    ['Warlock\'s Roll'] = {
        lucky=4, unlucky=8, desc='Magic Accuracy', values={
            [0]={2,3,4,10,4,5,6,1,7,7,12},
        }, bust=4,
    },
    
    ['Fighter\'s Roll'] = {
        lucky=5, unlucky=9, desc='Double Attack', percent=true, values={
            [0]={2,2,3,4,12,5,6,7,1,9,18},
        }, bust=6,
    },

    ['Puppet Roll'] = {
        lucky=4, unlucky=8, desc='Pet: Accuracy', values={
            [0]={10,13,15,40,18,20,25,5,28,30,50},
        }, bust=15,
    },
    ['Gallant\'s Roll'] = {
        lucky=3, unlucky=7, desc='Reflects Damage', percent=true, values={
            [0]={4,5,15,6,7,8,3,9,10,12,20},
        }, bust=10,
    },
    
    ['Wizard\'s Roll'] = {
        lucky=5, unlucky=9, desc='Magic Attack Bonus', values={
            [0]={2,3,4,4,10,5,6,7,1,7,12},
        }, bust=4,
    },
    
    ['Dancer\'s Roll'] = {
        lucky=3, unlucky=7, desc='Regen', values={
            [0]={3,4,11,4,5,6,1,7,8,8,14},
        }, bust=3,
    },
    
    ['Scholar\'s Roll'] = {
        lucky=2, unlucky=6, desc='Conserve MP', percent=true, values={
            [0]={2,10,3,4,4,1,5,6,7,7,12},
        }, bust=3,
    },
}
