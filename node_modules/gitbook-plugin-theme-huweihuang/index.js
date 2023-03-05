
module.exports = {
    hooks: {
        config: function(config) {
            config.styles = config.styles || config.pluginsConfig['theme-huweihuang'].styles;

            return config;
        }
    }
};


